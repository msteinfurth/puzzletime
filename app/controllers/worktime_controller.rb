# encoding: utf-8

# (c) Puzzle itc, Berne
# Diplomarbeit 2149, Xavier Hayoz

class WorktimeController < ApplicationController

  include ApplicationHelper

  before_action :authenticate
  helper_method :record_other?
  hide_action :detailAction


  FINISH = 'Abschliessen'


  def index
    redirect_to controller: 'evaluator', action: userEvaluation, clear: 1
  end

  # Shows the add time page.
  def add
    createDefaultWorktime
    setWorktimeDefaults
    setAccounts
    setExisting
    render action: 'add'
  end

  # Stores the new time the data on DB.
  def create
    setNewWorktime
    setWorktimeParams
    params[:other] = 1 if params[:worktime][:employee_id] && @user.management
    @worktime.employee = @user unless record_other?
    if @worktime.save
      flash[:notice] = "Die #{@worktime.class.label} wurde erfasst."
      checkOverlapping
      return unless processAfterCreate
      return listDetailTime if params[:commit] == FINISH
      @worktime = @worktime.template
    end
    setAccounts
    setExisting
    render action: 'add'
  end

  # Shows the edit page for the selected time.
  def edit
    setWorktime
    setWorktimeDefaults
    setAccounts true
    setExisting
    render action: 'edit'
  end

  # Update the selected worktime on DB.
  def update
    setWorktime
    if @worktime.employee_id != @user.id
      return listDetailTime if @worktime.absence?
      session[:split] = WorktimeEdit.new(@worktime.clone)
      createPart
    else
      @old_worktime = find_worktime if update_corresponding?
      setWorktimeParams
      if @worktime.save
        flash[:notice] = "Die #{@worktime.class.label} wurde aktualisiert."
        checkOverlapping
        return unless processAfterUpdate
        update_corresponding if update_corresponding?
        listDetailTime
      else
        setAccounts true
        setExisting
        render action: 'edit'
      end
    end
  end

  def confirm_delete
    setWorktime
    render action: 'confirm_delete'
  end

  def delete
    setWorktime
    if @worktime.employee == @user
      if @worktime.destroy
        flash[:notice] = "Die #{@worktime.class.label} wurde entfernt"
      else
        # errors enumerator yields attr and message (=second item)
        flash[:notice] = @worktime.errors.collect(&:second).join(', ')
      end
    end
    referer = request.headers['Referer']
    if params[:back] && referer && !(referer =~ /time\/edit\/#{@worktime.id}$/)
      referer.gsub!(/time\/create[^A-Z]?/, 'time/add')
      referer.gsub!(/time\/update[^A-Z]?/, 'time/edit')
      if referer.include?('work_date')
        referer.gsub!(/work_date=[0-9]{4}\-[0-9]{2}\-[0-9]{2}/, "work_date=#{@worktime.work_date}")
      else
        referer += (referer.include?('?') ? '&' : '?') + "work_date=#{@worktime.work_date}"
      end
      redirect_to(referer)
    else
      listDetailTime
    end
  end

  def view
    setWorktime
    render action: 'view'
  end

  def split
    @split = session[:split]
    if @split.nil?
      redirect_to controller: 'projecttime', action: 'add'
      return
    end
    @worktime = @split.worktimeTemplate
    setProjectAccounts
    render action: 'split'
  end

  def createPart
    @split = session[:split]
    return create if @split.nil?
    params[:id] ? setWorktime : setNewWorktime
    @worktime.employee ||= @split.original.employee
    setWorktimeParams
    if @worktime.valid? && @split.addWorktime(@worktime)
      if @split.complete? || (params[:commit] == FINISH && @split.class::INCOMPLETE_FINISH)
        @split.save
        session[:split] = nil
        flash[:notice] = 'Alle Arbeitszeiten wurden erfasst'
        if @worktime.employee != @user
          params[:other] = 1
          params[:evaluation] = nil
        end
        listDetailTime
      else
        session[:split] = @split
        redirect_to evaluation_detail_params.merge!(action: 'split')
      end
    else
      setProjectAccounts
      render action: 'split'
    end
  end

  def deletePart
    session[:split].removeWorktime(params[:part_id].to_i)
    redirect_to evaluation_detail_params.merge!(action: 'split')
  end

  def running
    if request.env['HTTP_USER_AGENT'] =~ /.*iPhone.*/
      render action: 'running', layout: 'phone'
    else
      render action: 'running'
    end
  end

  # ajax action
  def existing
    @worktime = Worktime.new
    begin
      @worktime.work_date = Date.strptime(params[:worktime][:work_date].to_s, DATE_FORMAT)
   rescue ArgumentError
      # invalid string, date will remain unaffected, i.e., nil
    end
    @worktime.employee_id = @user.management ? params[:worktime][:employee_id] : @user.id
    setExisting
    render action: 'existing'
  end

  # no action, may overwrite in subclass
  def detailAction
    'details'
  end

  protected

  def createDefaultWorktime
    set_period
    setNewWorktime
    @worktime.from_start_time = Time.zone.now.change(hour: DEFAULT_START_HOUR)
    @worktime.report_type = @user.report_type || DEFAULT_REPORT_TYPE
    if params[:work_date]
      @worktime.work_date = params[:work_date]
    elsif @period && @period.length == 1
      @worktime.work_date = @period.startDate
    else
      @worktime.work_date = Date.today
    end
    @worktime.employee_id = record_other? ? params[:employee_id] : @user.id
  end

  def setWorktimeParams
    @worktime.attributes = model_params
  end

  def listDetailTime
    options = evaluation_detail_params
    options[:controller] = 'evaluator'
    options[:action] = detailAction
    if params[:evaluation].nil?
      options[:evaluation] = userEvaluation
      options[:category_id] = @worktime.employee_id
      options[:division_id] = nil
      options[:clear] = 1
      set_period
      if @period.nil? || ! @period.include?(@worktime.work_date)
        period = Period.weekFor(@worktime.work_date)
        options[:start_date] = period.startDate
        options[:end_date] = period.endDate
      end
    end
    redirect_to options
  end

  def checkOverlapping
    if @worktime.report_type.is_a? StartStopType
      conditions = ['(project_id IS NULL AND absence_id IS NULL) AND ' \
                    'employee_id = :employee_id AND work_date = :work_date AND id <> :id AND (' +
                    '(from_start_time <= :start_time AND to_end_time >= :end_time) OR ' +
                    '(from_start_time >= :start_time AND from_start_time < :end_time) OR ' +
                    '(to_end_time > :start_time AND to_end_time <= :end_time))',
                    { employee_id: @worktime.employee_id,
                      work_date: @worktime.work_date,
                      id: @worktime.id,
                      start_time: @worktime.from_start_time,
                      end_time: @worktime.to_end_time }]
      conditions[0] = ' NOT ' + conditions[0] unless @worktime.is_a? Attendancetime
      overlaps = Worktime.where(conditions).to_a
      flash[:notice] += " Es besteht eine &Uuml;berlappung mit mindestens einem anderen Eintrag: <br/>\n" unless overlaps.empty?
      flash[:notice] += overlaps.join("<br/>\n") unless overlaps.empty?
    end
  end

  def setWorktime
    @worktime = find_worktime
  end

  def setExisting
    @work_date = @worktime.work_date
    @existing = Worktime.where('employee_id = ? AND work_date = ?', @worktime.employee_id, @work_date).
                         order('type DESC, from_start_time, project_id')
  end

  def find_worktime
    Worktime.find(params[:id])
  end

  # overwrite in subclass
  def setNewWorktime
    @worktime = nil
  end

  # overwrite in subclass
  def setWorktimeDefaults
  end

  # overwrite in subclass
  def setAccounts(all = false)
    @accounts = nil
  end

  def setProjectAccounts
    @accounts = @worktime.employee.leaf_projects
  end

  # may overwrite in subclass
  def userEvaluation
    record_other? ? 'employeeprojects' : 'userProjects'
  end

  def record_other?
    @user.management && params[:other]
  end

  def update_corresponding?
    false
  end

  def update_corresponding
    corresponding = @old_worktime.find_corresponding
    label = @old_worktime.corresponding_type.label
    if corresponding
      corresponding.copy_from @worktime
      if corresponding.save
        flash[:notice] += " Die zugehörige #{label} wurde angepasst."
      else
        flash[:notice] += " Die zugehörige #{label} konnte nicht angepasst werden (#{corresponding.errors.full_messages.join ', '})."
      end
    else
      flash[:notice] += " Es konnte keine zugehörige #{label} gefunden werden."
    end
  end

  # may overwrite in subclass
  # return whether normal proceeding should continue or another action was taken
  def processAfterSave
    true
  end

  def processAfterCreate
    processAfterSave
  end

  def processAfterUpdate
    processAfterSave
  end

  ################   RUNNING TIME FUNCTIONS    ##################

  def startRunning(time, start = Time.zone.now)
    time.employee = @user
    time.report_type = AutoStartType::INSTANCE
    time.work_date = start.to_date
    time.from_start_time = start
    time.billable = time.project.billable if time.project
    saveRunning time, "Die #{time.account ? 'Projektzeit ' + time.account.label_verbose : 'Anwesenheit'} mit #timeString wurde erfasst.\n"
  end

  def stopRunning(time = runningTime, stop = Time.zone.now)
    time.to_end_time = time.work_date == Date.today ? stop : '23:59'
    time.report_type = StartStopType::INSTANCE
    time.store_hours
    if time.hours < 0.0166
      append_flash "#{time.class.label} unter einer Minute wird nicht erfasst.\n"
      time.destroy
      runningTime(true)
    else
      saveRunning time, "Die #{time.account ? 'Projektzeit ' + time.account.label_verbose : 'Anwesenheit'} von #timeString wurde gespeichert.\n"
    end
  end

  def saveRunning(time, message)
    if time.save
      append_flash message.sub('#timeString', time.timeString)
    else
      append_flash "Die #{time.class.label} konnte nicht gespeichert werden:\n"
      time.errors.each { |attr, msg| flash[:notice] += '<br/> - ' + msg + "\n" }
    end
    runningTime(true)
    time
  end

  def runningTime(reload = false)
    # implement in subclass
  end

  def redirect_to_running
    redirect_to controller: 'worktime', action: 'running'
  end

  def append_flash(msg)
    flash[:notice] = flash[:notice] ? flash[:notice] + '<br/>' + msg : msg
  end
end
