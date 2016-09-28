# encoding: utf-8

module Plannings
  class Board

    attr_reader :subject, :period, :employees

    def initialize(subject, period)
      @subject = subject
      @period = period
    end

    def caption
      subject.label_verbose
    end

    def for_rows(keys)
      @rows = nil
      @included_rows = keys
    end

    def items(employee_id, work_item_id)
      rows[key(employee_id, work_item_id)]
    end

    def work_days
      @work_days ||= period.length / 7 * 5
    end

    def rows
      @rows ||= build_rows
    end

    def week_totals
      @week_totals ||= Hash.new(0.0).tap do |totals|
        load_plannings.group(:date).sum(:percent).each do |date, percent|
          totals[date.at_beginning_of_week.to_date] += percent / 5.0
        end
      end
    end

    def week_totals_state(_date)
      nil
    end

    def accounting_posts
      rows
      @accounting_posts ||= load_accounting_posts
    end

    private

    def build_rows
      load_data
      {}.tap do |rows|
        build_default_rows(rows)
        build_planning_rows(rows)
        add_absencetimes_to_rows(rows)
      end
    end

    def load_data
      @plannings = load_plannings.where(included_plannings_condition)
      @employees = load_employees
      @absencetimes = load_absencetimes
    end

    def build_default_rows(rows)
      Array(@included_rows).each do |key|
        rows[key] = empty_row
      end
    end

    def build_planning_rows(rows)
      @plannings.each do |p|
        k = key(p.employee_id, p.work_item_id)
        rows[k] = empty_row unless rows.key?(k)
        index = item_index(p.date)
        rows[k][index] = p if index
      end
    end

    def add_absencetimes_to_rows(rows)
      @absencetimes.each do |time|
        rows.each do |key, items|
          if key.first == time.employee_id
            index = item_index(time.work_date)
            items[index] = time if index
          end
        end
      end
    end

    def item_index(date)
      return if [0, 6, 7].include?(date.wday)
      diff = (date - period.start_date).to_i
      diff - (diff / 7 * 2).to_i
    end

    def key(employee_id, work_item_id)
      [employee_id, work_item_id]
    end

    def empty_row
      Array.new(work_days)
    end

    def load_plannings
      Planning.in_period(period).list
    end

    def load_accounting_posts
      AccountingPost
        .where(work_item_id: included_work_item_ids)
        .includes(:work_item)
        .list
    end

    def load_employees
      Employee.where(id: included_employee_ids).list
    end

    def load_absencetimes
      Absencetime.in_period(period).includes(:absence).where(employee_id: included_employee_ids)
    end

    def included_plannings_condition
      return if @included_rows.nil?
      return '0 = 1' if @included_rows.blank?

      [''].tap do |condition|
        @included_rows.each do |employee_id, work_item_id|
          condition[0] += ' OR ' unless condition.first.blank?
          condition[0] += '(plannings.work_item_id = ? AND plannings.employee_id = ?)'
          condition << work_item_id << employee_id
        end
      end
    end

    def included_employee_ids
      included_key_ids(:employee_id, :first).uniq
    end

    def included_work_item_ids
      included_key_ids(:work_item_id, :last).uniq
    end

    def included_key_ids(name, position)
      @included_rows ? @included_rows.map(&position) : @plannings.map(&name)
    end

  end
end
