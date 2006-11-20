# (c) Puzzle itc, Berne
# Diplomarbeit 2149, Xavier Hayoz

class Absence < ActiveRecord::Base

  include Division
  
  # All dependencies between the models are listed below
  has_many :worktimes, :dependent => true
  has_many :employees, :through => :worktimes, :order => "lastname"

  # Validation helpers
  validates_presence_of :name
  validates_uniqueness_of :name
  
  def self.list
    find(:all, :order => 'name')
  end
   
end
