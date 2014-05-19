class AbsencetimeController < WorktimeController

  def addMultiAbsence
    setAccounts
    @multiabsence = MultiAbsence.new
  end

  def createMultiAbsence
    @multiabsence = MultiAbsence.new
    @multiabsence.employee = @user
    @multiabsence.attributes = params[:multiabsence]
    if @multiabsence.valid?
      count = @multiabsence.save
      flash[:notice] = "#{count} Absenzen wurden erfasst"
      options = { controller: 'evaluator',
                  action: detailAction,
                  evaluation: userEvaluation,
                  clear: 1 }
      set_period
      if @period.nil? ||
          (! @period.include?(@multiabsence.start_date) ||
          ! @period.include?(@multiabsence.end_date))
        options[:start_date] = @multiabsence.start_date
        options[:end_date] = @multiabsence.end_date
      end
      redirect_to options
    else
      setAccounts
      render action: 'addMultiAbsence'
    end
  end

  protected

  def setNewWorktime
    @worktime = Absencetime.new
  end

  def setWorktimeDefaults
    @worktime.absence_id ||= params[:account_id]
  end

  def setAccounts(all = false)
    @accounts = Absence.list
  end

  def userEvaluation
    @user.absences(true)
    record_other? ? 'employeeabsences' : 'userAbsences'
  end

  def model_params
    attrs = [:account, :report_type, :work_date, :hours,
             :from_start_time, :to_end_time, :description]
    attrs << :emloyee_id if @user.management
    params.require(:worktime).permit(attrs)
  end
end
