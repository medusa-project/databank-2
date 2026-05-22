class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("IDB_MAIL_FROM", "no-reply@databank.illinois.edu")
  layout nil
end
