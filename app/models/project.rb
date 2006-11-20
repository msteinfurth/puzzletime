# (c) Puzzle itc, Berne
# Diplomarbeit 2149, Xavier Hayoz

class Project < ActiveRecord::Base
  
  include Category
  include Division

  # All dependencies between the models are listed below.
  has_many :projectmemberships, :dependent => true, :finder_sql => 
    'SELECT m.* FROM projectmemberships m, employees e ' +
    'WHERE e.id = m.employee_id ' +
    'ORDER BY e.lastname, e.firstname'
  has_many :employees, :through => :projectmemberships, :order => "lastname"
  belongs_to :client
  has_many :worktimes
  
  # Validation helpers.  
  validates_presence_of :name
  validates_uniqueness_of :name
  
  def self.list
    self.find(:all, :order => 'name')
  end
  
  def fullname
    client.name + ' - ' + name
  end

end
