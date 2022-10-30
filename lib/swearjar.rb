# frozen_string_literal: true

require 'yaml'
require 'emoji_regex'

class Swearjar
  DEFAULT_SENSOR_MASK = '*'
  WORD_REGEX = /\b[a-zA-Z-]+\b/

  def self.default
    from_language('en')
  end

  def self.from_language(language)
    new(File.join(File.dirname(__FILE__), 'config', "#{language}.yml"))
  end

  def initialize(file = nil)
    @hash = {}
    @regexs = {}
    load_file(file) if file
  end

  def profane?(string)
    string = string.to_s
    scan(string) {|test| return true if test }
    false
  end

  def scorecard(string)
    string = string.to_s
    scorecard = {}
    scan(string) do |test|
      next unless test
      test.each do |type|
        scorecard[type] = 0 unless scorecard.key?(type)
        scorecard[type] += 1
      end
    end
    scorecard
  end

  def censor(string, censor_mask = DEFAULT_SENSOR_MASK)
    censored_string = string.to_s.dup
    scan(string) do |test, word, position|
      next unless test
      replacement = block_given? ? yield(word) : word.gsub(/\S/, censor_mask)
      censored_string[position, word.size] = replacement
    end
    censored_string
  end

  private

  def load_file(file)
    data = YAML.load_file(file)

    data['regex'].each do |pattern, type|
      @regexs[Regexp.new(pattern, "i")] = type
    end if data['regex']

    data['simple'].each do |test, type|
      @hash[test] = type
    end if data['simple']

    data['emoji'].each do |unicode, type|
      char = unicode_to_emoji(unicode)
      @hash[char] = type
    end if data['emoji']
  end

  def scan(string, &block)
    string.scan(WORD_REGEX) do |word|
      position = Regexp.last_match.offset(0)[0]
      test = @hash[word.downcase] ||
        @hash[word.downcase.sub(/s\z/,'')] ||
        @hash[word.downcase.sub(/es\z/,'')]
      block.call(test, word, position)
    end

    string.scan(EmojiRegex::Regex) do |emoji_char|
      position = Regexp.last_match.offset(0)[0]
      emoji = emoji_without_skin_tone(emoji_char)
      block.call(@hash[emoji], emoji_char, position)
    end

    @regexs.each do |regex, type|
      string.scan(regex) do |word|
        position = Regexp.last_match.offset(0)[0]
        block.call(type, word, position)
      end
    end
  end

  private

  def unicode_to_emoji(hex_string)
    [hex_string.hex].pack('U')
  end

  def emoji_without_skin_tone(emoji)
    bytes = emoji.unpack('UU')
    unicode_to_emoji(bytes[0].to_s(16))
  end
end
