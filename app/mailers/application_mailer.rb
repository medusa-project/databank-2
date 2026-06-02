class ApplicationMailer < ActionMailer::Base
  default from: IdbConfig.fetch(:mail, :from, default: "no-reply@databank.illinois.edu")
  layout nil
end
