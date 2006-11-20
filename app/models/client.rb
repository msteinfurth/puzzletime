# (c) Puzzle itc, Berne
# Diplomarbeit 2149, Xavier Hayoz

class Client < ActiveRecord::Base

  include Category

  # All dependencies between the models are listed below.
  has_many :projects, :order => "name"
  
  # Validation helpers.
  validates_presence_of :name
  validates_uniqueness_of :name
   
  def self.list 
    find(:all, :order => "name")  
  end
  
  def subdivisionRef
    0
  end
  
  def detailFor(time)
    time.employee.shortname
  end
end
