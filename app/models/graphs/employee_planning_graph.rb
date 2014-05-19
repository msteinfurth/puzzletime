# encoding: utf-8

class EmployeePlanningGraph

  include PlanningHelper

  attr_reader :period, :plannings, :plannings_abstr, :projects, :projects_abstr, :employee, :overview_graph, :absence_graph

  def initialize(employee, period = nil)
    @employee = employee
    period ||= Period.currentMonth
    @actual_period = period
    @period = extend_to_weeks(period)
    @cache = {}
    @colorMap = AccountColorMapper.new
    employee_plannings = Planning.where('start_week <= ?', Week.from_date(@period.endDate).to_integer).
                                  where(employee_id: @employee.id)
    @plannings       = employee_plannings.where(is_abstract: false)
    @plannings_abstr = employee_plannings.where(is_abstract: true)
    @projects       = collect_projects(@plannings)
    @projects_abstr = collect_projects(@plannings_abstr)
    absences = Absencetime.where('employee_id = ? AND work_date >= ? AND work_date <= ?',
                                 @employee.id, @period.startDate, @period.endDate)
    @absence_graph = AbsencePlanningGraph.new(absences, @period)
    @overview_graph = EmployeeOverviewPlanningGraph.new(@employee, @plannings, @plannings_abstr, absence_graph, @period)
  end

  def collect_projects(plannings)
    plannings.select { |planning| planning.planned_during?(@period) }.
              collect { |planning| planning.project }.
              uniq.
              sort
  end

end