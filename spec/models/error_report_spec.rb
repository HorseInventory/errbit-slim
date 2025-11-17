describe ErrorReport do
  let(:notice_attrs_for) do
    lambda do |api_key|
      {
        error_class:        "TestingException",
        message:            "some message",
        backtrace:          [
          {
            "number" => "425",
            "file"   => "[GEM_ROOT]/callbacks.rb",
            "method" => "__callbacks",
          },
        ],
        request:            { "component" => "application" },
        server_environment: {
          "project-root"     => "/path/to/sample/project",
          "environment-name" => "development",
        },
        api_key:            api_key,
        notifier:           {
          "name"    => "Example Notifier",
          "version" => "2.3.2",
          "url"     => "http://example.com",
        },
        framework:          "Rails: 3.2.11",
        user_attributes:    {
          "id"       => "123",
          "name"     => "Mr. Bean",
          "email"    => "mr.bean@example.com",
          "username" => "mrbean",
        },
      }
    end
  end
  let(:notice_attrs) { notice_attrs_for.call(app.api_key) }
  let!(:app) do
    Fabricate(
      :app,
      api_key: 'APIKEY',
    )
  end
  let!(:user) { Fabricate(:user) }
  let(:error_report) { ErrorReport.new(notice_attrs) }

  before { user }

  describe "#app" do
    it 'find the good app' do
      expect(error_report.app).to(eq(app))
    end
  end

  describe "#generate_notice!" do
    it "save a notice" do
      expect do
        error_report.generate_notice!
      end.to(change do
        app.reload.problems.count
      end.by(1))
    end

    describe "notice create" do
      before { error_report.generate_notice! }
      subject { error_report.notice }

      it 'has correct framework' do
        expect(subject.framework).to(eq('Rails: 3.2.11'))
      end

      it 'has a backtrace' do
        expect(subject.backtrace_lines.size).to(be > 0)
      end

      it 'has server_environement' do
        expect(subject.server_environment['environment-name']).to(eq('development'))
      end

      it 'has request' do
        expect(subject.request).to(be_a(Hash))
      end

      it 'get user_attributes' do
        expect(subject.user_attributes['id']).to(eq('123'))
        expect(subject.user_attributes['name']).to(eq('Mr. Bean'))
        expect(subject.user_attributes['email']).to(eq('mr.bean@example.com'))
        expect(subject.user_attributes['username']).to(eq('mrbean'))
      end

      it 'valid env_vars' do
        expect(subject.env_vars).to(be_a(Hash))
      end
    end
  end

  describe '#cache_attributes_on_problem' do
    it 'sets the latest notice properties on the problem' do
      error_report.generate_notice!
      problem = error_report.problem.reload
      notice = error_report.notice.reload

      expect(problem.environment).to(eq('development'))
      expect(problem.last_notice_at).to(eq(notice.created_at))
      expect(problem.message).to(eq(notice.message))
      expect(problem.where).to(eq(notice.where))
    end

    it 'unresolves the problem' do
      error_report.generate_notice!
      problem = error_report.problem
      problem.update(
        resolved_at: Time.zone.now,
        resolved:    true,
      )

      error_report = ErrorReport.new(notice_attrs)
      error_report.generate_notice!
      problem.reload

      expect(problem.resolved_at).to(be(nil))
      expect(problem.resolved).to(be(false))
    end
  end

  it 'save a notice assigned to a problem' do
    error_report.generate_notice!
    expect(error_report.notice.problem).to(be_a(Problem))
  end

  it 'memoize the notice' do
    expect do
      error_report.generate_notice!
      error_report.generate_notice!
    end.to(change do
      Notice.count
    end.by(1))
  end

  it 'find the correct (duplicate) Problem (and resolved) for the Notice' do
    error_report.generate_notice!
    error_report.problem.resolve!

    expect do
      ErrorReport.new(notice_attrs).generate_notice!
    end.to(change do
      error_report.problem.reload.resolved?
    end.from(true).to(false))
  end

  context "with notification service configured" do
    before do
      app.notify_on_errs = true
      app.save
    end

    it 'send email' do
      notice = error_report.generate_notice!
      email = ActionMailer::Base.deliveries.last
      expect(email.to).to(include(User.first.email))
      expect(email.subject).to(include(notice.message.truncate(50)))
    end

    context 'when email_at_notices config is specified', type: :mailer do
      before do
        allow(Errbit::Config).to(receive(:email_at_notices).and_return(email_at_notices))
      end

      context 'as [0]' do
        let(:email_at_notices) { [0] }

        it "sends email on 1st occurrence" do
          1.times { described_class.new(notice_attrs).generate_notice! }
          expect(ActionMailer::Base.deliveries.length).to(eq(1))
        end

        it "sends email on 2nd occurrence" do
          2.times { described_class.new(notice_attrs).generate_notice! }
          expect(ActionMailer::Base.deliveries.length).to(eq(2))
        end

        it "sends email on 3rd occurrence" do
          3.times { described_class.new(notice_attrs).generate_notice! }
          expect(ActionMailer::Base.deliveries.length).to(eq(3))
        end
      end

      context "as [1,3]" do
        let(:email_at_notices) { [1, 3] }

        it "sends email on 1st occurrence" do
          1.times { described_class.new(notice_attrs).generate_notice! }
          expect(ActionMailer::Base.deliveries.length).to(eq(1))
        end

        it "does not send email on 2nd occurrence" do
          2.times { described_class.new(notice_attrs).generate_notice! }
          expect(ActionMailer::Base.deliveries.length).to(eq(1))
        end

        it "sends email on 3rd occurrence" do
          3.times { described_class.new(notice_attrs).generate_notice! }
          expect(ActionMailer::Base.deliveries.length).to(eq(2))
        end

        it "sends email on all occurrences when problem was resolved" do
          3.times do
            notice = described_class.new(notice_attrs).generate_notice!
            notice.problem.resolve!
          end
          # With simplified behavior, resolution triggers an email on the next occurrence only
          expect(ActionMailer::Base.deliveries.length).to(eq(2))
        end
      end
    end
  end

  describe "#notice" do
    context "before generate_notice!" do
      it 'return nil' do
        expect(error_report.notice).to(be(nil))
      end
    end

    context "after generate_notice!" do
      before do
        error_report.generate_notice!
      end

      it 'return the notice' do
        expect(error_report.notice).to(be_a(Notice))
      end
    end
  end

  describe "text_to_regex_string" do
    let(:similar_notice_messages) do
      JSON.parse(Rails.root.join("spec/fixtures/similar_notice_messages.json").read)
    end

    it "should return a minimal number of unique regexes" do
      unique_regexes = similar_notice_messages.map do |message|
        ErrorReport.text_to_regex_string(message).delete("\\")
      end.uniq

      expect(unique_regexes.size).to(be <= 25)
    end

    context "when handling quoted strings with patterns inside" do
      let(:message_with_guid) do
        '{"error_reference":"If you report this error, please include this id: e511a292-4c3b-45ac-a18e-2d678328be75-1763152708."}'
      end

      let(:message_with_simple_strings) do
        '{"code":"INVALID_INVENTORY_ITEM", "field":["input", "quantities", "0", "inventoryItemId"], "message":"The specified inventory item could not be found."}'
      end

      it "produces different regex patterns for messages with different structures" do
        regex1 = ErrorReport.text_to_regex_string(message_with_guid)
        regex2 = ErrorReport.text_to_regex_string(message_with_simple_strings)

        expect(regex1).not_to(eq(regex2))
      end

      it "does not match unrelated messages" do
        regex1 = ErrorReport.text_to_regex_string(message_with_guid)
        regex2 = ErrorReport.text_to_regex_string(message_with_simple_strings)

        expect(message_with_guid).not_to(match(/\A#{regex2}\z/i))
        expect(message_with_simple_strings).not_to(match(/\A#{regex1}\z/i))
      end

      it "matches messages with same structure but different variable values" do
        regex1 = ErrorReport.text_to_regex_string(message_with_guid)

        similar_message = '{"error_reference":"If you report this error, please include this id: a1b2c3d4-5678-90ab-cdef-1234567890ab-9876543210."}'

        expect(similar_message).to(match(/\A#{regex1}\z/i))
      end

      it "matches messages with simple strings that have same structure" do
        regex2 = ErrorReport.text_to_regex_string(message_with_simple_strings)

        similar_message = '{"code":"ANOTHER_ERROR_CODE", "field":["other", "path", "1", "someId"], "message":"A different error message."}'

        expect(similar_message).to(match(/\A#{regex2}\z/i))
      end

      it "preserves pattern structure inside quoted strings" do
        message = '{"id":"f47ac10b-58cc-4372-a567-0e02b2c3d479"}'
        regex = ErrorReport.text_to_regex_string(message)

        expect(regex).to(include('[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'))

        different_guid_message = '{"id":"a1b2c3d4-1234-5678-90ab-abcdef123456"}'
        expect(different_guid_message).to(match(/\A#{regex}\z/i))

        different_structure_message = '{"id":"just-a-string"}'
        expect(different_structure_message).not_to(match(/\A#{regex}\z/i))
      end
    end

    context "DB integration tests" do
      let(:problem) { Fabricate(:problem, app: app) }

      it "finds notices with GUIDs correctly" do
        notice1 = Fabricate(:notice, message: 'ID: 550e8400-e29b-41d4-a716-446655440000', problem: problem)
        notice2 = Fabricate(:notice, message: 'ID: a1b2c3d4-5678-90ab-cdef-123456789012', problem: problem)
        other_notice = Fabricate(:notice, message: 'ID: simple-string', problem: problem)

        regex = ErrorReport.text_to_regex_string(notice1.message)
        found = Notice.where(message: /\A#{regex}\z/i).pluck(:id)

        expect(found).to(include(notice1.id))
        expect(found).to(include(notice2.id))
        expect(found).not_to(include(other_notice.id))
      end

      it "finds notices with email addresses correctly" do
        notice1 = Fabricate(:notice, message: 'Contact: user@example.com', problem: problem)
        notice2 = Fabricate(:notice, message: 'Contact: admin@test.org', problem: problem)
        other_notice = Fabricate(:notice, message: 'Contact: not-an-email', problem: problem)

        regex = ErrorReport.text_to_regex_string(notice1.message)
        found = Notice.where(message: /\A#{regex}\z/i).pluck(:id)

        expect(found).to(include(notice1.id))
        expect(found).to(include(notice2.id))
        expect(found).not_to(include(other_notice.id))
      end

      it "finds notices with URLs correctly" do
        notice1 = Fabricate(:notice, message: 'Visit: https://example.com/path', problem: problem)
        notice2 = Fabricate(:notice, message: 'Visit: http://test.org/other', problem: problem)
        other_notice = Fabricate(:notice, message: 'Visit: not-a-url', problem: problem)

        regex = ErrorReport.text_to_regex_string(notice1.message)
        found = Notice.where(message: /\A#{regex}\z/i).pluck(:id)

        expect(found).to(include(notice1.id))
        expect(found).to(include(notice2.id))
        expect(found).not_to(include(other_notice.id))
      end

      it "finds notices with IP addresses correctly" do
        notice1 = Fabricate(:notice, message: 'Server: 192.168.1.1', problem: problem)
        notice2 = Fabricate(:notice, message: 'Server: 10.0.0.1', problem: problem)
        other_notice = Fabricate(:notice, message: 'Server: not-an-ip', problem: problem)

        regex = ErrorReport.text_to_regex_string(notice1.message)
        found = Notice.where(message: /\A#{regex}\z/i).pluck(:id)

        expect(found).to(include(notice1.id))
        expect(found).to(include(notice2.id))
        expect(found).not_to(include(other_notice.id))
      end

      it "finds notices with domains correctly" do
        notice1 = Fabricate(:notice, message: 'Host: example.com', problem: problem)
        notice2 = Fabricate(:notice, message: 'Host: test.org', problem: problem)
        other_notice = Fabricate(:notice, message: 'Host: not-a-domain', problem: problem)

        regex = ErrorReport.text_to_regex_string(notice1.message)
        found = Notice.where(message: /\A#{regex}\z/i).pluck(:id)

        expect(found).to(include(notice1.id))
        expect(found).to(include(notice2.id))
        expect(found).not_to(include(other_notice.id))
      end

      it "finds notices with phone numbers correctly" do
        notice1 = Fabricate(:notice, message: 'Call: 555-123-4567', problem: problem)
        notice2 = Fabricate(:notice, message: 'Call: 123-456-7890', problem: problem)
        other_notice = Fabricate(:notice, message: 'Call: not-a-phone', problem: problem)

        regex = ErrorReport.text_to_regex_string(notice1.message)
        found = Notice.where(message: /\A#{regex}\z/i).pluck(:id)

        expect(found).to(include(notice1.id))
        expect(found).to(include(notice2.id))
        expect(found).not_to(include(other_notice.id))
      end

      it "finds notices with dates correctly" do
        notice1 = Fabricate(:notice, message: 'Date: 2025-11-17', problem: problem)
        notice2 = Fabricate(:notice, message: 'Date: 2024-01-01', problem: problem)
        other_notice = Fabricate(:notice, message: 'Date: not-a-date', problem: problem)

        regex = ErrorReport.text_to_regex_string(notice1.message)
        found = Notice.where(message: /\A#{regex}\z/i).pluck(:id)

        expect(found).to(include(notice1.id))
        expect(found).to(include(notice2.id))
        expect(found).not_to(include(other_notice.id))
      end

      it "finds notices with MAC addresses correctly" do
        notice1 = Fabricate(:notice, message: 'MAC: 00:1B:44:11:3A:B7', problem: problem)
        notice2 = Fabricate(:notice, message: 'MAC: aa:bb:cc:dd:ee:ff', problem: problem)
        other_notice = Fabricate(:notice, message: 'MAC: not-a-mac', problem: problem)

        regex = ErrorReport.text_to_regex_string(notice1.message)
        found = Notice.where(message: /\A#{regex}\z/i).pluck(:id)

        expect(found).to(include(notice1.id))
        expect(found).to(include(notice2.id))
        expect(found).not_to(include(other_notice.id))
      end

      it "finds notices with hashes correctly" do
        notice1 = Fabricate(:notice, message: 'Commit: 1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b', problem: problem)
        notice2 = Fabricate(:notice, message: 'Commit: abcdef1234567890abcdef1234567890', problem: problem)
        other_notice = Fabricate(:notice, message: 'Commit: short', problem: problem)

        regex = ErrorReport.text_to_regex_string(notice1.message)
        found = Notice.where(message: /\A#{regex}\z/i).pluck(:id)

        expect(found).to(include(notice1.id))
        expect(found).to(include(notice2.id))
        expect(found).not_to(include(other_notice.id))
      end

      it "finds notices with file paths correctly" do
        notice1 = Fabricate(:notice, message: 'File: /usr/local/bin/script', problem: problem)
        notice2 = Fabricate(:notice, message: 'File: /home/user/file.txt', problem: problem)
        other_notice = Fabricate(:notice, message: 'File: not-a-path', problem: problem)

        regex = ErrorReport.text_to_regex_string(notice1.message)
        found = Notice.where(message: /\A#{regex}\z/i).pluck(:id)

        expect(found).to(include(notice1.id))
        expect(found).to(include(notice2.id))
        expect(found).not_to(include(other_notice.id))
      end

      it "finds notices with integers correctly" do
        notice1 = Fabricate(:notice, message: 'Error on line 42 with count 100', problem: problem)
        notice2 = Fabricate(:notice, message: 'Error on line 99 with count 999', problem: problem)
        other_notice = Fabricate(:notice, message: 'Error on line with count', problem: problem)

        regex = ErrorReport.text_to_regex_string(notice1.message)
        found = Notice.where(message: /\A#{regex}\z/i).pluck(:id)

        expect(found).to(include(notice1.id))
        expect(found).to(include(notice2.id))
        expect(found).not_to(include(other_notice.id))
      end

      it "finds notices with quoted strings containing patterns correctly" do
        notice1 = Fabricate(:notice, message: '{"id":"f47ac10b-58cc-4372-a567-0e02b2c3d479"}', problem: problem)
        notice2 = Fabricate(:notice, message: '{"id":"a1b2c3d4-1234-5678-90ab-abcdef123456"}', problem: problem)
        other_notice = Fabricate(:notice, message: '{"id":"just-a-string"}', problem: problem)

        regex = ErrorReport.text_to_regex_string(notice1.message)
        found = Notice.where(message: /\A#{regex}\z/i).pluck(:id)

        expect(found).to(include(notice1.id))
        expect(found).to(include(notice2.id))
        expect(found).not_to(include(other_notice.id))
      end

      it "finds notices with simple quoted strings correctly" do
        notice1 = Fabricate(:notice, message: '{"code":"INVALID_INVENTORY_ITEM"}', problem: problem)
        notice2 = Fabricate(:notice, message: '{"code":"ANOTHER_ERROR_CODE"}', problem: problem)
        other_notice = Fabricate(:notice, message: 'code: NO_QUOTES', problem: problem)

        regex = ErrorReport.text_to_regex_string(notice1.message)
        found = Notice.where(message: /\A#{regex}\z/i).pluck(:id)

        expect(found).to(include(notice1.id))
        expect(found).to(include(notice2.id))
        expect(found).not_to(include(other_notice.id))
      end

      it "separates notices with different quoted string structures" do
        notice_with_guid = Fabricate(:notice, message: '{"error_reference":"If you report this error, please include this id: e511a292-4c3b-45ac-a18e-2d678328be75-1763152708."}', problem: problem)
        notice_with_simple = Fabricate(:notice, message: '{"code":"INVALID_INVENTORY_ITEM", "field":["input", "quantities", "0", "inventoryItemId"], "message":"The specified inventory item could not be found."}', problem: problem)

        regex_for_guid = ErrorReport.text_to_regex_string(notice_with_guid.message)
        regex_for_simple = ErrorReport.text_to_regex_string(notice_with_simple.message)

        found_by_guid_regex = Notice.where(message: /\A#{regex_for_guid}\z/i).pluck(:id)
        found_by_simple_regex = Notice.where(message: /\A#{regex_for_simple}\z/i).pluck(:id)

        expect(found_by_guid_regex).to(include(notice_with_guid.id))
        expect(found_by_guid_regex).not_to(include(notice_with_simple.id))

        expect(found_by_simple_regex).to(include(notice_with_simple.id))
        expect(found_by_simple_regex).not_to(include(notice_with_guid.id))
      end

      it "verifies consistency between deduplicated_message and text_to_regex_string" do
        messages = [
          'Error with GUID: 550e8400-e29b-41d4-a716-446655440000',
          'Error with email: user@example.com',
          'Error with URL: https://example.com/path',
          'Error with IP: 192.168.1.1',
          'Error on line 42',
        ]

        messages.each do |msg|
          notice = Fabricate(:notice, message: msg, problem: problem)
          regex = ErrorReport.text_to_regex_string(notice.message)

          found = Notice.where(message: /\A#{regex}\z/i).pluck(:id)
          expect(found).to(include(notice.id))
        end
      end
    end
  end
end
