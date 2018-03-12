#! /bin/ruby

require 'optparse'
require 'ostruct'
require 'pathname'
require 'date'
require 'erb'

#
# ----------------------------------------------------------------------
# Settings
# ----------------------------------------------------------------------
#

#
# ----------------------------------------------------------------------
# Command line handling.
# ----------------------------------------------------------------------
#

class CmdLine
  def self.parse(args)
    options = OpenStruct.new
    options.inputDirectory = ""
    options.outputDirectory = ""
    options.me = nil
    options.senderIdMap = {}

    opt_parser = OptionParser.new do |opts|
      opts.banner = "Usage: c2h.rb [options]"
      opts.on("-i", "--inputDirectory=DIR", "Directory containing _chat.txt.") do |i|
        options.inputDirectory = i
      end
      opts.on("-o", "--outputDirectory=DIR", "Output directory, will be created or cleaned.") do |o|
        options.outputDirectory = o
      end
      opts.on("--me=senderId", "Right-align messages by this sender.") do |me|
        options.me = me
      end
      opts.on("--map=<senderId=name>,...", Array, "Map sender ids to proper names.") do |list|
        list.each { |map|
          senderId, name = map.split("=")
          options.senderIdMap[senderId] = name
        }
      end
      opts.on_tail("-h", "--help", "Show this message.") do
        puts opts
        exit
      end
    end

    opt_parser.parse!(args)
    options
  end
end

options = CmdLine.parse(ARGV)

if options.inputDirectory.empty? or options.outputDirectory.empty?
  CmdLine.parse(["-h"]) # exits
end

inputDir = Pathname.new(options.inputDirectory)
outputDir = Pathname.new(options.outputDirectory)
chatTxtFileName = inputDir.join("_chat.txt")

if !chatTxtFileName.readable?
  puts "Oops: \"" + chatTxtFileName.to_s + "\" does not exist or is not readable."
  exit
end

#
# Create output directory if it does not exist.
#

if !outputDir.directory? and !outputDir.exist?
  outputDir.mkdir()
end

if !outputDir.directory?
  puts "Oops: \"" + outputDir.to_s + "\" is not a directory."
  exit
end

#
# To make sure that we do not delete anything important, we test that
# the directory is either empty or that it contains an "index.html"
# file.
#

if outputDir.directory?
  contents = Dir.entries(outputDir)
  contents.delete(".")
  contents.delete("..")
  if !contents.empty? and !contents.include?("index.html")
    puts "Oops: \"" + outputDir.to_s + "\" is not empty."
    exit
  end
end

#
# ----------------------------------------------------------------------
# Input file parsing.
# ----------------------------------------------------------------------
#

#
# Read chat file in binary so that ruby does not touch line endings.
#

chatTxtFile = File.open(chatTxtFileName, "rb")
chatTxt = chatTxtFile.read
chatTxtFile.close

#
# Message lines are separated by CR LF.
#

messages = Hash.new
senderIds = Hash.new

chatTxt.split("\r\n").each { |messageLine|
  #
  # Force message to UTF-8 after reading the file in binary.
  #

  messageLine = messageLine.force_encoding("UTF-8")

  #
  # Each message line starts with a "date, time:"
  #

  timestampMatch = messageLine.match('^\d{2}.\d{2}.\d{2}, \d{2}:\d{2}:\d{2}:')
  raise "Oops" if timestampMatch == nil

  endOfTimestamp = timestampMatch.end(0)
  timestampString = messageLine[0..endOfTimestamp-1].strip
  timestamp = DateTime.strptime(timestampString, "%d.%m.%y, %H:%M:%S")

  #
  # After the timestamp, there is usually the sender ID followed by a ":".
  # Assumption: system messages never contain a ":".
  #

  endOfSenderId = messageLine.index(":", endOfTimestamp+1)

  if endOfSenderId
    senderId = messageLine[endOfTimestamp+1..endOfSenderId-1].strip
    message = messageLine[endOfSenderId+1..-1].strip
  else
    senderId = nil
    message = messageLine[endOfTimestamp+1..-1].strip
  end

  #
  # For attachments, the message looks like "filename <attached>", where
  # the string "attached" is localized. It looks like there is either
  # text or an attachment, but not both. If an attachment has a comment,
  # the comment is not exported.
  #

  if attachmentMatch = message.match('([0-9A-Z-]+\.[a-z]+)\s<[^\s>]+>')
    message = nil
    attachment = attachmentMatch[1]
  else
    attachment = nil
  end

  #
  # Index sender ids.
  #

  if senderId and !senderIds.include?(senderId)
    senderIds[senderId] = true

    if options.me and senderId.include?(options.me)
      options.me = senderId
    end

    options.senderIdMap.keys.each { |key|
      if senderId.include?(key)
        options.senderIdMap[senderId] = options.senderIdMap[key]
      end
    }
  end

  #
  # Index messages by "year-month-day"
  #

  date=timestamp.strftime("%Y-%m-%d")

  if !messages.include?(date)
    messages[date] = Array.new
  end

  messages[date] << {
    "timestamp" => timestamp,
    "senderId" => senderId,
    "text" => message,
    "attachment" => attachment
  }
}

#
# If there are only two sender ids, and the "me" option was not given,
# choose one of them as "me."
#

if senderIds.size == 2 and options.me == nil
  options.me = senderIds.values[0]
end

#
# ----------------------------------------------------------------------
# Output generation.
# ----------------------------------------------------------------------
#

def uniToHtml(message)
  html=""
  i=0
  l=message.length
  s=0
  while i < l
    if ! message[i].ascii_only?
      cp = message[i].codepoints[0]
      if s != i
        html.concat(message[s..i-1])
      end
      html.concat("&#%d;" % cp)
      s = i + 1
    end
    i = i + 1
  end
  return html.concat(message[s..-1])
end

def replaceUrlsWithLinks(message)
  s = 0
  result = ""
  urlRegex = "http[s]?://(?:[a-zA-Z]|[0-9]|[$-_@.&+]|[!*\(\),]|(?:%[0-9a-fA-F][0-9a-fA-F]))+"
  while urlMatch = message.match(urlRegex, s)
    if urlMatch.begin(0) > s
      result.concat(message[s..urlMatch.begin(0)-1])
    end
    result.concat("<a href=\"")
    result.concat(urlMatch[0]);
    result.concat("\">")
    result.concat(urlMatch[0])
    result.concat("</a>")
    s = urlMatch.end(0)
  end
  return result.concat(message[s..-1])
end

def formatMessageText(message)
  return replaceUrlsWithLinks(uniToHtml(message))
end

#
# Copy style sheet file to output directory.
#

scriptFileName = Pathname.new($0)
scriptDirectory = scriptFileName.dirname
cssBaseName = "c2h.css"
IO.copy_stream(scriptDirectory.join(cssBaseName), outputDir.join(cssBaseName))

indexHtmlFileName = outputDir.join("index.html")
indexHtmlFile = File.open(indexHtmlFileName, "w")
indexHtmlFile.puts("<html>
<head>
<link rel=\"stylesheet\" href=\"c2h.css\">
</head>
<body>")

messages.each_key { |date|
  timestamp = Date.strptime(date, "%Y-%m-%d")
  indexHtmlFile.puts("<hr>")
  indexHtmlFile.puts("<div class=\"date\"><p align=\"center\">")
  indexHtmlFile.puts(timestamp.strftime("%-d. %B %Y"))
  indexHtmlFile.puts("</p></div>")
  indexHtmlFile.puts("<hr>")

  messages[date].each { |message|
    #
    # Is this a message from "me"?
    #

    isMyMessage = message["senderId"] == options.me

    #
    # Map senderId.
    #

    senderIdToPrint = message["senderId"]
    if options.senderIdMap.include?(senderIdToPrint)
      senderIdToPrint = options.senderIdMap[senderIdToPrint]
    end

    if message["senderId"] and !message["attachment"]
      #
      # Regular user message.
      #

      if isMyMessage
        msgClass = "userMessage-Me"
      else
        msgClass = "userMessage-Them"
      end

      indexHtmlFile.puts("<div class=\"overflow\">")
      indexHtmlFile.puts("<div class=\"#{msgClass} userMessage\">")

      if senderIds.size != 2 and !isMyMessage
        indexHtmlFile.puts("<b>" + uniToHtml(senderIdToPrint) + "</b> ")
      end

      indexHtmlFile.puts(formatMessageText(message["text"]))
      indexHtmlFile.puts("<div class=\"timestamp\">")
      indexHtmlFile.puts(message["timestamp"].strftime("%H:%M"))
      indexHtmlFile.puts("</div>")
      indexHtmlFile.puts("</div>")
      indexHtmlFile.puts("</div>")
    elsif message["senderId"] and message["attachment"]
      #
      # Attachment.
      #

      attachmentFileName = Pathname.new(message["attachment"])
      attachmentFileType = attachmentFileName.extname[1..-1]

      if attachmentFileType == "jpg" or attachmentFileType == "png"
        inputFileName = inputDir.join(attachmentFileName)
        outputFileName = outputDir.join(attachmentFileName)
        # IO.copy_stream(inputFileName, outputFileName)
        indexHtmlFile.puts("<div class=\"userMessage\">")

        if senderIds.size != 2
          indexHtmlFile.puts("<b>" + uniToHtml(senderIdToPrint) + "</b> ")
        end

        indexHtmlFile.puts("<img width=\"50%\" src=\"" + attachmentFileName.to_s + "\">")
        indexHtmlFile.puts("</div>")
      end
    elsif !message["senderId"]
      #
      # System message.
      #

      indexHtmlFile.puts("<div class=\"systemMessage\">")
      indexHtmlFile.puts("<p align=\"center\">")
      indexHtmlFile.puts(uniToHtml(message["text"]))
      indexHtmlFile.puts("</p>")
      indexHtmlFile.puts("</div>")
    end
  }
}

indexHtmlFile.puts("</body>")
indexHtmlFile.puts("</html>")
indexHtmlFile.close()
