describe Backtrace, type: 'model' do
  describe '.find_or_build' do
    let(:lines) do
      [
        { 'number' => '123', 'file' => '/some/path/to.rb', 'method' => 'abc' },
        { 'number' => '345', 'file' => '/path/to.rb', 'method' => 'dowhat' }
      ]
    end
    let(:fingerprint) { Backtrace.generate_fingerprint(lines) }

    it 'builds a new backtrace' do
      backtrace = described_class.find_or_build(lines)

      expect(backtrace.lines).to(eq(lines))
      expect(backtrace.fingerprint).to(eq(fingerprint))
      expect(backtrace).to(be_new_record)
    end

    it 'reuses an existing backtrace with the same lines' do
      backtrace = described_class.find_or_build(lines)
      backtrace.save!

      expect(described_class.find_or_build(lines)).to(eq(backtrace))
      expect(Backtrace.where(fingerprint: fingerprint).count).to(eq(1))
    end
  end
end
