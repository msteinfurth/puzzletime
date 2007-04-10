class Splitable

  attr_reader :original, :worktimes
  
  def initialize(original)
    @original = original
    @worktimes = []
  end
  
  def addWorktime(worktime)
    @worktimes.push(worktime)
  end
  
  def removeWorktime(index)
    @worktimes.delete_at(index)
  end

  def worktimeTemplate
    worktime = lastWorktime.template
    worktime.hours = remainingHours
    worktime.from_start_time = nextStartTime
    worktime.to_end_time = original.to_end_time
    return worktime
  end
    
  def incomplete?
    remainingHours > 0.00001     # we are working with floats: use delta
  end
  
  def save
    worktimes.each { |wtime|  wtime.save }
  end
  
protected
  
  def remainingHours
    original.hours - worktimes.inject(0) {|sum, time| sum + time.hours}
  end
  
  def nextStartTime
    worktimes.empty? ? 
      original.from_start_time :
      worktimes.last.to_end_time    
  end
  
  def lastWorktime
    worktimes.empty? ? original : worktimes.last
  end
  
end