namespace :errbit do
  desc 'Mark existing compressed occurrences and create the notice indexes'
  task prepare_notice_retention: :environment do
    compressed = Notice.collection.find(server_environment: {})
    backtrace_ids = compressed.distinct(:backtrace_id).compact
    compressed.update_many('$set' => { compressed: true, backtrace_id: nil })
    Notice.collection.find(server_environment: { '$ne' => {} }).update_many('$set' => { compressed: false })
    Backtrace.delete_unreferenced(backtrace_ids)
    Notice.create_indexes
  end
end
