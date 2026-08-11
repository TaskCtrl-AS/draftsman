class Enumable < ActiveRecord::Base
  has_drafts
  if ActiveRecord::VERSION::STRING.to_f >= 7.0
    enum :status, { active: 0, archived: 1 }
  else
    enum status: { active: 0, archived: 1 }
  end
end
