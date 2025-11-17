module PatternMatching
  GUID_PATTERN = '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
  DOMAIN_PATTERN = '[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+'
  IP_PATTERN = '(?:\d{1,3}\.){3}\d{1,3}'
  INTEGER_PATTERN = '\d+'
  EMAIL_PATTERN = '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
  PHONE_PATTERN = '\(?[1-9]\d{2}\)?[ \-\.]?[1-9]\d{2}[ \-\.]?\d{4}'
  DATE_PATTERN = '\d{4}-\d{2}-\d{2}(?:T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+\-]\d{2}:?\d{2})?)?'
  URL_PATTERN = 'https?://[^\s]+'
  FILE_PATH_PATTERN = '(\/[A-Za-z0-9._]+)+'
  MAC_ADDRESS_PATTERN = '[0-9a-fA-F]{2}(?::[0-9a-fA-F]{2}){5}'
  HASH_PATTERN = '[0-9a-fA-F]{7,64}'
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

  # Used for nicely displaying the message in the UI
  def self.deduplicated_message(message)
    message.gsub(PATTERN_REGEXES[0], '<GUID>').
      gsub(PATTERN_REGEXES[1], '<EMAIL>').
      gsub(PATTERN_REGEXES[2], '<URL>').
      gsub(PATTERN_REGEXES[3], '<FILE_PATH>').
      gsub(PATTERN_REGEXES[4], '<MAC_ADDRESS>').
      gsub(PATTERN_REGEXES[5], '<HASH>').
      gsub(PATTERN_REGEXES[6], '<DATE>').
      gsub(PATTERN_REGEXES[7], '<PHONE>').
      gsub(PATTERN_REGEXES[8], '<IP>').
      gsub(PATTERN_REGEXES[9], '<DOMAIN>').
      gsub(PATTERN_REGEXES[10], '<INTEGER>').
      gsub(quoted_string_pattern_omit_others, '<QUOTED_STRING>')
  end

  def self.quoted_string_pattern_omit_others
    /"(?:(?!<[A-Z_]+>)[^"])*"|'(?:(?!<[A-Z_]+>)[^'])*'|"<[A-Z_]+>"|'<[A-Z_]+>'/
  end
end
