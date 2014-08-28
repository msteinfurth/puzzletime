# encoding: utf-8

# (c) Puzzle itc, Berne
# Diplomarbeit 2149, Xavier Hayoz

class WorktimesController < CrudController

  helper_method :record_other?

  before_action :authorize_destroy, only: :destroy

  after_save :check_overlapping

  before_render_index :set_statistics
  before_render_new :create_default_worktime
  before_render_form :set_existing
  before_render_form :set_employees

  FINISH = 'Abschliessen'

  def index
    set_week_days
    @notifications = UserNotification.list_during(@period)
    super
  end

  def show
    redirect_to index_url
  end

  def new
    super do |format|
      if params[:template]
        template = Worktime.find(params[:template])
        @worktime.account_id = template.account_id
        @worktime.ticket = template.ticket
        @worktime.description = template.description
        @worktime.billable = template.billable
      end
    end
  end

  # ajax action
  def existing
    @worktime = Worktime.new
    @worktime.work_date = model_params[:work_date]
    @worktime.employee_id = @user.management ? model_params[:employee_id].presence || @user.id : @user.id
    set_existing
    render 'existing'
  end

  private

  def create_default_worktime
    set_period
    entry
    set_work_date
    @worktime.employee_id = employee_id
    set_worktime_defaults
    true
  end

  def set_work_date
    unless @worktime.work_date
      if params[:work_date]
        @worktime.work_date = params[:work_date]
      elsif @period && @period.length == 1
        @worktime.work_date = @period.start_date
      else
        @worktime.work_date = Date.today
      end
    end
  end

  def authorize_destroy
    unless entry.employee == @user
      flash[:notice] = 'Sie sind nicht authorisiert, um diese Seite zu öffnen'
      redirect_to root_path
    end
  end

  def check_overlapping
    if @worktime.report_type.is_a? StartStopType
      conditions = ['NOT (project_id IS NULL AND absence_id IS NULL) AND ' \
                    'employee_id = :employee_id AND work_date = :work_date AND id <> :id AND (' +
                    '(from_start_time <= :start_time AND to_end_time >= :end_time) OR ' +
                    '(from_start_time >= :start_time AND from_start_time < :end_time) OR ' +
                    '(to_end_time > :start_time AND to_end_time <= :end_time))',
                    { employee_id: @worktime.employee_id,
                      work_date: @worktime.work_date,
                      id: @worktime.id,
                      start_time: @worktime.from_start_time,
                      end_time: @worktime.to_end_time }]
      overlaps = Worktime.where(conditions).includes(:project).to_a
      if overlaps.present?
        flash[:notice] += " Es besteht eine Überlappung mit mindestens einem anderen Eintrag: <br/>\n".html_safe
        flash[:notice] += overlaps.collect { |o| ERB::Util.h(o) }.join("<br/>\n").html_safe
      end
    end
  end

  def set_existing
    @work_date = @worktime.work_date
    @existing = Worktime.where('employee_id = ? AND work_date = ?', @worktime.employee_id, @work_date).
                         order('type DESC, from_start_time, project_id').
                         includes(:project, :absence)
  end

  def set_week_days
    @selected_date = params[:week_date].present? ? Date.parse(params[:week_date]) : Date.today
    @week_days = (@selected_date.at_beginning_of_week..@selected_date.at_end_of_week).to_a
    @next_week_date = @week_days.last + 1.day
    @previous_week_date = @week_days.first - 7.day
  end

  def set_employees
    @employees = Employee.list if record_other?
  end

  def list_entries
    @worktimes = Worktime.where('employee_id = ? AND work_date >= ? AND work_date <= ?', @user.id, @week_days.first, @week_days.last)
                         .includes(:project, :absence)
                         .order('work_date, from_start_time, project_id')
    @daily_worktimes = @worktimes.group_by{ |w| w.work_date }
    @worktimes
  end

  def index_url
    if params[:back_url].present?
      sanitized_back_url
    elsif record_other?
      week = Period.week_for(entry.work_date)
      { controller: 'evaluator',
        action: 'details',
        evaluation: generic_evaluation,
        division_id: employee_id,
        start_date: week.start_date,
        end_date: week.end_date,
        clear: 1 }
    else
      { action: 'index', week_date: entry.work_date }
    end
  end

  def set_statistics
    @current_overtime = @user.statistics.current_overtime
    @monthly_worktime = @user.statistics.musttime(Period.current_month)
    @pending_worktime = 0 - @user.statistics.overtime(Period.current_month).to_f
    @remaining_vacations = @user.statistics.current_remaining_vacations
  end

  # returns the employee's id from the params or the logged in user
  def employee_id
    if record_other?
      params.key?(model_identifier) ? model_params[:employee_id] : params[:employee_id]
    else
      @user.id
    end
  end

  # overwrite in subclass
  def set_worktime_defaults
  end

  def record_other?
    @user.management && (%w(1 true).include?(params[:other]) || other_employee_param?)
  end

  def other_employee_param?
    params.key?(model_identifier) &&
    model_params[:employee_id] &&
    model_params[:employee_id] != @user.id
  end

  def append_flash(msg)
    flash[:notice] = flash[:notice] ? flash[:notice] + '<br/>'.html_safe + msg : msg
  end

  def permitted_attrs
    attrs = self.class.permitted_attrs.clone
    attrs << :employee_id if @user.management
    attrs
  end

  def assign_attributes
    if params.key?(model_identifier)
      params[:other] = '1' if model_params[:employee_id] && @user.management
      super
      entry.employee = @user unless record_other?
      if model_params[:from_start_time].present? || model_params[:to_end_time].present?
        entry.hours = nil
        entry.report_type = StartStopType::INSTANCE
      else
        entry.from_start_time = nil
        entry.to_end_time = nil
        entry.report_type = HoursDayType::INSTANCE
      end
    end
  end

  def generic_evaluation
    'employees'
  end

  def ivar_name(klass)
    klass < Worktime ? Worktime.model_name.param_key : super(klass)
  end

end
