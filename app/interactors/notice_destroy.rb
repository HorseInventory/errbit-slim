class NoticeDestroy
  def initialize(notices)
    @notices = notices
  end

  def execute
    backtrace_ids = @notices.distinct(:backtrace_id).compact
    @notices.delete_all
    Backtrace.delete_unreferenced(backtrace_ids)
  end
end
