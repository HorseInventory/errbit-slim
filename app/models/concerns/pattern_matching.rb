module PatternMatching
  GUID_PATTERN = '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
  EMAIL_PATTERN = '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
  URL_PATTERN = 'https?://[^\s]+'
  FILE_PATH_PATTERN = '(\/[A-Za-z0-9._]+)+'
  MAC_ADDRESS_PATTERN = '[0-9a-fA-F]{2}(?::[0-9a-fA-F]{2}){5}'
  HASH_PATTERN = '[0-9a-fA-F]{7,64}'
  DATE_PATTERN = '\d{4}-\d{2}-\d{2}(?:T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+\-]\d{2}:?\d{2})?)?'
  PHONE_PATTERN = '\(?[1-9]\d{2}\)?[ \-\.]?[1-9]\d{2}[ \-\.]?\d{4}'
  IP_PATTERN = '(?:\d{1,3}\.){3}\d{1,3}'
  DOMAIN_PATTERN = '[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+'
  INTEGER_PATTERN = '\d+'
  QUOTED_STRING_PATTERN = '"[^"]*"|\'[^\']*\''

  PATTERN_CONSTANTS = [
    GUID_PATTERN,
    EMAIL_PATTERN,
    URL_PATTERN,
    FILE_PATH_PATTERN,
    MAC_ADDRESS_PATTERN,
    HASH_PATTERN,
    DATE_PATTERN,
    PHONE_PATTERN,
    IP_PATTERN,
    DOMAIN_PATTERN,
    INTEGER_PATTERN,
    QUOTED_STRING_PATTERN,
  ]

  PATTERN_REGEXES = [
    /\b#{GUID_PATTERN}\b/,
    /\b#{EMAIL_PATTERN}\b/,
    /\b#{URL_PATTERN}\b/,
    /#{FILE_PATH_PATTERN}/,
    /\b#{MAC_ADDRESS_PATTERN}\b/,
    /\b#{HASH_PATTERN}\b/,
    /\b#{DATE_PATTERN}\b/,
    /\b#{PHONE_PATTERN}\b/,
    /\b#{IP_PATTERN}\b/,
    /\b#{DOMAIN_PATTERN}\b/,
    /\b#{INTEGER_PATTERN}\b/,
    /#{QUOTED_STRING_PATTERN}/,
  ]

  VARIABLE_REGEX = Regexp.union(*PATTERN_REGEXES)

  # Used for finding similar Notices in the DB
  def self.text_to_regex_string(input_str)
    result = +"" # mutable string
    last_pos = 0

    input_str.scan(VARIABLE_REGEX) do
      match = Regexp.last_match
      match_start = match.begin(0)
      match_end   = match.end(0)
      variable_text = match[0]

      # Add the literal (escaped) text up to the start of this match
      literal_text = input_str[last_pos...match_start]
      result << Regexp.escape(literal_text)

      # Handle quoted strings - check if they contain patterns
      if /\A#{QUOTED_STRING_PATTERN}\z/.match?(variable_text)
        quote_char = variable_text[0]
        content = variable_text[1..-2]
        has_patterns, processed_content = process_quoted_content_for_regex(content)

        if has_patterns
          result << Regexp.escape(quote_char) << processed_content << Regexp.escape(quote_char)
        else
          # No patterns inside, use generic quoted string pattern
          result << (quote_char == '"' ? '"[^"]*"' : "'[^']*'")
        end
      else
        # Find which pattern matched and use its string version
        pattern = PATTERN_CONSTANTS.find { |p| variable_text =~ /\A#{p}\z/ }
        result << (pattern || Regexp.escape(variable_text))
      end

      last_pos = match_end
    end

    # Add any leftover text after the final match
    leftover = input_str[last_pos..-1]
    result << Regexp.escape(leftover) if leftover

    result
  end

  # Helper to process content of a quoted string for text_to_regex_string
  def self.process_quoted_content_for_regex(content)
    non_quoted_regex = Regexp.union(*PATTERN_REGEXES[0..-2])
    has_patterns = false
    processed = +""
    last_pos = 0

    content.scan(non_quoted_regex) do
      match = Regexp.last_match
      processed << Regexp.escape(content[last_pos...match.begin(0)])

      inner_pattern = PATTERN_CONSTANTS.find { |p| match[0] =~ /\A#{p}\z/ }
      processed << (inner_pattern || Regexp.escape(match[0]))
      has_patterns = true

      last_pos = match.end(0)
    end

    processed << Regexp.escape(content[last_pos..-1])

    # If content is ONLY a pattern (no other text), hide it (match deduplicated_message behavior)
    if has_patterns && PATTERN_CONSTANTS[0..-2].any? { |p| processed == p }
      has_patterns = false
    end

    [has_patterns, processed]
  end

  # Used for nicely displaying the message in the UI
  def self.deduplicated_message(message)
    # First pass: replace patterns outside of quoted strings (with word boundaries)
    result = message.gsub(PATTERN_REGEXES[0], '<GUID>').
      gsub(PATTERN_REGEXES[1], '<EMAIL>').
      gsub(PATTERN_REGEXES[2], '<URL>').
      gsub(PATTERN_REGEXES[3], '<FILE_PATH>').
      gsub(PATTERN_REGEXES[4], '<MAC_ADDRESS>').
      gsub(PATTERN_REGEXES[5], '<HASH>').
      gsub(PATTERN_REGEXES[6], '<DATE>').
      gsub(PATTERN_REGEXES[7], '<PHONE>').
      gsub(PATTERN_REGEXES[8], '<IP>').
      gsub(PATTERN_REGEXES[9], '<DOMAIN>').
      gsub(PATTERN_REGEXES[10], '<INTEGER>')

    # Second pass: process quoted strings (without word boundaries for patterns)
    result.gsub(/#{QUOTED_STRING_PATTERN}/) do |matched_string|
      quote_char = matched_string[0]
      content = matched_string[1..-2]

      # Check if already has replaced patterns from first pass
      has_replaced_patterns = content.match?(/<[A-Z_]+>/)

      # Replace patterns inside without word boundaries (excluding INTEGER per existing tests)
      processed_content = content.
        gsub(/#{GUID_PATTERN}/, '<GUID>').
        gsub(/#{EMAIL_PATTERN}/, '<EMAIL>').
        gsub(/#{URL_PATTERN}/, '<URL>').
        gsub(/#{MAC_ADDRESS_PATTERN}/, '<MAC_ADDRESS>').
        gsub(/#{HASH_PATTERN}/, '<HASH>').
        gsub(/#{FILE_PATH_PATTERN}/, '<FILE_PATH>').
        gsub(/#{DATE_PATTERN}/, '<DATE>').
        gsub(/#{PHONE_PATTERN}/, '<PHONE>').
        gsub(/#{IP_PATTERN}/, '<IP>').
        gsub(/#{DOMAIN_PATTERN}/, '<DOMAIN>')

      # Keep quotes visible only if patterns were found AND there's other text besides the pattern
      if (has_replaced_patterns || processed_content != content) && processed_content !~ /\A<[A-Z_]+>\z/
        "#{quote_char}#{processed_content}#{quote_char}"
      else
        '<QUOTED_STRING>'
      end
    end
  end

  def self.quoted_string_pattern_omit_others
    /"(?:(?!<[A-Z_]+>)[^"])*"|'(?:(?!<[A-Z_]+>)[^'])*'|"<[A-Z_]+>"|'<[A-Z_]+>'/
  end
end
