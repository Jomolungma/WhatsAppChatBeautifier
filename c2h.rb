#! /bin/ruby

require 'optparse'
require 'ostruct'
require 'pathname'
require 'date'

#
# ----------------------------------------------------------------------
# Settings
# ----------------------------------------------------------------------
#

$thumbWidth = 320
$thumbHeight = 240
$emojiWidth = 20
$emojiHeight = 20

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
    options.title = nil
    options.me = nil
    options.senderIdMap = {}
    options.copyMedia = true
    options.verbose = 0
    options.indexByMonth = false
    options.indexByYear = false
    options.emojiDir = nil

    opt_parser = OptionParser.new do |opts|
      opts.banner = "Usage: c2h.rb [options]"
      opts.on("-i", "--inputDirectory=DIR", "Directory containing _chat.txt.") do |i|
        options.inputDirectory = i
      end
      opts.on("-o", "--outputDirectory=DIR", "Output directory, will be created or cleaned.") do |o|
        options.outputDirectory = o
      end
      opts.on("-t", "--title=Title", "Chat title.") do |t|
        options.title = t
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
      opts.on("--[no-]copyMedia", "Copy media files.") do |c|
        options.copyMedia = c
      end
      opts.on("-x", "--indexBy=[month,year]", "Create daily, monthly or annual index.") do |x|
        if x.downcase == "month"
          options.indexByMonth = true
        elsif x.downcase == "year"
          options.indexByYear = true
        else
          raise "Invalid value for --indexBy option: \"#{x}\""
        end
      end
      opts.on("-e", "--emojiDir=directory", "Use emoji image files from this directory.") do |e|
        options.emojiDir = e
      end
      opts.on("-v", "--verbose", "Increase verbosity.") do
        options.verbose = options.verbose + 1
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

$options = CmdLine.parse(ARGV)

if $options.inputDirectory.empty? or $options.outputDirectory.empty?
  CmdLine.parse(["-h"]) # exits
end

$inputDir = Pathname.new($options.inputDirectory)
$outputDir = Pathname.new($options.outputDirectory)
chatTxtFileName = $inputDir.join("_chat.txt")

if !chatTxtFileName.readable?
  puts "Oops: \"" + chatTxtFileName.to_s + "\" does not exist or is not readable."
  exit
end

#
# Create output directory if it does not exist.
#

if !$outputDir.directory? and !$outputDir.exist?
  $outputDir.mkdir()
end

if !$outputDir.directory?
  puts "Oops: \"" + $outputDir.to_s + "\" is not a directory."
  exit
end

#
# To make sure that we do not delete anything important, we test that
# the directory is either empty or that it contains an "index.html"
# file.
#

if $outputDir.directory?
  contents = Dir.entries($outputDir)
  contents.delete(".")
  contents.delete("..")
  if !contents.empty? and !contents.include?("index.html")
    puts "Oops: \"" + $outputDir.to_s + "\" is not empty."
    exit
  end
end

#
# Gather list of emoji files if an emoji directory is given.
#

$emojiFiles = Hash.new

if $options.emojiDir
  $emojiDir = Pathname.new($options.emojiDir)
  Dir.entries($emojiDir).each { |fileName|
    if fileName[-4..-1] == ".png"
      imageBaseName = fileName[0..-5]
      $emojiFiles[imageBaseName] = false
    end
  }
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

messageCount = 0
messages = Hash.new
$senderIds = Hash.new
$allYears = Hash.new
$allMonths = Hash.new

chatTxt.split("\r\n").each { |messageLine|
  #
  # Force message to UTF-8 after reading the file in binary.
  #

  messageLine = messageLine.force_encoding("UTF-8")

  #
  # Each message line starts with a "date, time:", sometimes preceded by a
  # unicode character.
  #

  timestampMatch = messageLine.match('(\[)?(\d{2}.\d{2}.\d{2}, \d{2}:\d{2}:\d{2})(\])?(:)?')
  raise "Oops" if timestampMatch == nil

  beginOfTimestamp = timestampMatch.begin(2)
  endOfTimestamp = timestampMatch.end(2)
  timestampString = messageLine[beginOfTimestamp..endOfTimestamp-1].strip
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
  # For attachments, the message looks like "filename [* n pages] <attached>",
  # where the strings "attached" and "pages" are localized. The "n pages" is
  # present for PDF attachments.
  #
  # There is either text or an attachment, but not both. If an attachment has a
  # comment, the comment is not exported.
  #

  if attachmentMatch = message.match('([0-9A-Za-z\- ]+\.[A-Za-z0-9]+).*<[^\s>]+>')
    message = nil
    attachment = attachmentMatch[1]
  else
    attachment = nil
  end

  #
  # Index sender ids.
  #

  if senderId and !$senderIds.include?(senderId)
    $senderIds[senderId] = true
  end

  #
  # Index messages by "year-month-day"
  #

  year=timestamp.strftime("%Y")
  month=timestamp.strftime("%Y-%m")
  day=timestamp.strftime("%Y-%m-%d")

  $allYears[year] = true
  $allMonths[month] = true

  if !messages.include?(day)
    messages[day] = Array.new
  end

  messages[day] << {
    "timestamp" => timestamp,
    "senderId" => senderId,
    "text" => message,
    "attachment" => attachment
  }

  messageCount = messageCount + 1
}

#
# If there are only two sender ids, and the "me" option was not given,
# choose one of them as "me."
#

if $senderIds.size == 2 and $options.me == nil
  $options.me = $senderIds.keys[0]
end

#
# Cleanse sender ids for "me" and "map".
#

$senderIds.each_key { |senderId|
  if $options.me and senderId.include?($options.me)
    $options.me = senderId
  end

  $options.senderIdMap.keys.each { |key|
    if senderId.include?(key)
      $options.senderIdMap[senderId] = $options.senderIdMap[key]
    end
  }
}

#
# Get arrays of all years, months, days.
#

$allYears = $allYears.keys
$allMonths = $allMonths.keys
$allDays = messages.keys

#
# ----------------------------------------------------------------------
# Media file helpers.
# ----------------------------------------------------------------------
#

def pngSize(file)
  file.seek(0)
  pngSig = [137, 80, 78, 71, 13, 10, 26, 10].pack("C*")
  fileSig = file.read(8)
  if pngSig == fileSig
    chunkLength = file.read(4).unpack("N")[0]
    chunkType = file.read(4)
    if chunkLength == 13 and chunkType == "IHDR"
      width, height = file.read(13).unpack("NN")
      return ["PNG", width, height]
    end
  end
  return [nil, 0, 0]
end

def jpgSize(file)
  file.seek(0)
  jpgSig = [255, 216, 255, 224].pack("C*")
  fileSig = file.read(4)
  if jpgSig == fileSig
    app0Length = file.read(2).unpack("n")[0]
    app0Id = file.read(4)
    if app0Id == "JFIF"
      file.seek(4 + app0Length)
      while !file.eof?
        segMarker = file.read(2).unpack("C*")
        segLength = file.read(2).unpack("n")[0]
        if segMarker[0] == 255 and segMarker[1] == 192
          sof0Info = file.read(5).unpack("Cnn")
          return ["JPG", sof0Info[2], sof0Info[1]]
        end
        file.seek(segLength - 2, IO::SEEK_CUR)
      end
    end
  end
  return [nil, 0, 0]
end

def imageSize(filename)
  file = File.open(filename, "rb")

  imgFile, width, height = pngSize(file)

  if !imgFile
    imgFile, width, height = jpgSize(file)
  end

  file.close()
  return [imgFile, width, height]
end

#
# ----------------------------------------------------------------------
# Output generation.
# ----------------------------------------------------------------------
#

#
# Format a date string "January 1, 2018".
#

def formatDay(date)
  return date.strftime("%B %-d, %Y")
end

def formatMonth(date)
  return date.strftime("%B")
end

def formatYear(date)
  return date.strftime("%Y")
end

#
# Replace non-ascii characters in a message with their HTML encoding.
#

def uniToHtml(messageText)
  escapeCharacters="<>&"
  html=""
  i=0
  l=messageText.length
  s=0
  while i < l
    c = messageText[i]
    if !c.ascii_only? or escapeCharacters.index(c)
      cp = c.codepoints[0]
      if s != i
        html.concat(messageText[s..i-1])
      end
      html.concat("&#%d;" % cp)
      s = i + 1
    end
    i = i + 1
  end
  html.concat(messageText[s..-1])
  html.gsub("\n", "<br>")
end

#
# Replace emojis (after HTML encoding).
#

def eatConsecutiveUnicode(text)
  codepoints = []
  while md = text.match("^&#([0-9]+);")
    codepoints << md[1].to_i
    text = text[md.end(0)..-1]
  end
  return codepoints, text
end

def findLongestUnicodeEmojiSubsequence(codepoints)
  basename=codepoints.join("_")
  if codepoints.length > 0
    basename=codepoints.join("_")
    if $emojiFiles.include?(basename)
      return codepoints.length
    else
      return findLongestUnicodeEmojiSubsequence(codepoints[0..-2])
    end
  else
    return 0
  end
end

def replaceEmojisWithImages(messageText)
  output = ""
  while i = messageText.index('&')
    if i != 0
      output.concat(messageText[0..i-1])
    end
    codepoints, remainder = eatConsecutiveUnicode(messageText[i..-1])
    codepoints.delete_if { |cp| (cp >= 65024)  and (cp <= 65039)  } # Delete variation selectors.
    codepoints.delete_if { |cp| (cp >= 127995) and (cp <= 127999) } # Delete skin tone modifiers.

    while codepoints.length > 0
      hexCodepoints = codepoints.map { |cp| sprintf("%x",cp) }      # Map to hexadecimal.
      subLength = findLongestUnicodeEmojiSubsequence(hexCodepoints)
      if subLength > 0
        basename=hexCodepoints[0..subLength-1].join("_")
        output.concat("<img width=\"#{$emojiWidth}\" height=\"#{$emojiHeight}\" src=\"#{basename}.png\">")
        codepoints = codepoints[subLength..-1]
        $emojiFiles[basename] = true
      else
        output.concat(sprintf("&#%d;", codepoints[0]))
        codepoints = codepoints[1..-1]
      end
    end

    messageText = remainder
  end
  output.concat(messageText)
  return output
end

#
# Replace URLs in a message text with links to that URL.
#

def replaceUrlsWithLinks(messageText)
  s = 0
  result = ""
  urlRegex = "http[s]?://(?:[a-zA-Z]|[0-9]|[$-_@.&+]|[!*\(\),]|(?:%[0-9a-fA-F][0-9a-fA-F]))+"
  while urlMatch = messageText.match(urlRegex, s)
    if urlMatch.begin(0) > s
      result.concat(messageText[s..urlMatch.begin(0)-1])
    end
    result.concat("<a href=\"")
    result.concat(urlMatch[0]);
    result.concat("\">")
    result.concat(urlMatch[0])
    result.concat("</a>")
    s = urlMatch.end(0)
  end
  return result.concat(messageText[s..-1])
end

#
# Format message content.
#

def formatMessageText(messageText)
  return replaceEmojisWithImages(replaceUrlsWithLinks(uniToHtml(messageText)))
end

#
# Is this a message from "me"?
#

def isMyMessage(message)
  return message["senderId"] == $options.me
end

#
# Get CSS style to use for this message.
#

def getMsgClass(message)
  return isMyMessage(message) ? "userMessage-Me" : "userMessage-Them"
end

#
# Print senderId.
#

def printSenderId(file, message)
  senderIdToPrint = message["senderId"]
  if $options.senderIdMap.include?(senderIdToPrint)
    senderIdToPrint = $options.senderIdMap[senderIdToPrint]
  end

  #
  # Do not print sender id if:
  # - There are only two participants to the chat. (In this case, if the
  #   "--me" option was not given, one of them is chosen as "me".)
  # - There are more than two participants to the chat and the message is
  #   mine.
  #

  noSenderId = (($senderIds.size == 2) or isMyMessage(message))

  if !noSenderId
    file.puts("<span class=\"senderId\">" + uniToHtml(senderIdToPrint) + "</span> ")
  end
end

#
# Scale image.
#

def scaleImage(width, height)
  if width > $thumbWidth or height > $thumbHeight
    widthScale = width.to_f / $thumbWidth.to_f
    heightScale = height.to_f / $thumbHeight.to_f
    scale = (widthScale > heightScale) ? widthScale : heightScale
    newWidth = (width / scale).to_i
    newHeight = (height / scale).to_i
  else
    newWidth = width
    newHeight = height
  end
  return [newWidth, newHeight]
end

#
# Process a regular user message.
#

def processRegularUserMessage(file, message)
  file.puts(formatMessageText(message["text"]))
end

#
# Process a message that is an image attachment.
#

def processImageAttachmentMessage(file, attachmentFileName, inputFileName)
  #
  # If the "thumbnails" option is given, we check the image size, and scale
  # large images down to our "thumbnail" size.
  #

  imgFile, imgWidth, imgHeight = imageSize(inputFileName)

  if imgFile == nil
    file.puts("<img src=\"#{attachmentFileName.to_s}\">")
  else
    width, height = scaleImage(imgWidth, imgHeight)
    file.puts("<a href=\"#{attachmentFileName.to_s}\">")
    file.puts("<img width=\"#{width}\" height=\"#{height}\" src=\"" + attachmentFileName.to_s + "\">")
    file.puts("</a>")
  end
end

#
# Process a message that is an audio attachment.
#

def processAudioAttachmentMessage(file, attachmentFileName, inputFileName)
  file.puts("<audio controls=\"\">")
  file.puts("<source src=\"#{attachmentFileName.to_s}\">")
  file.puts("</audio>")
end

#
# Process a message that is an audio attachment.
#

def processVideoAttachmentMessage(file, attachmentFileName, inputFileName)
  file.puts("<video width=\"#{$thumbWidth}\" controls=\"\">")
  file.puts("<source src=\"#{attachmentFileName.to_s}\">")
  file.puts("</video>")
end

#
# Process a generic attachment (e.g., a PDF file).
#

def processGenericAttachmentMessage(file, attachmentFileName, inputFileName)
  file.puts("<a href=\"#{attachmentFileName.to_s}\">#{attachmentFileName.to_s}</a>")
end

#
# Process a message that is an attachment.
#

def processAttachmentMessage(file, message)
  attachmentFileName = Pathname.new(message["attachment"])
  attachmentFileType = attachmentFileName.extname[1..-1]

  inputFileName = $inputDir.join(attachmentFileName)

  if $options.copyMedia
    outputFileName = $outputDir.join(attachmentFileName)
    IO.copy_stream(inputFileName, outputFileName)
  end

  case (attachmentFileType)
    when "jpg", "png" then
      processImageAttachmentMessage(file, attachmentFileName, inputFileName)
    when "mp4" then
      processVideoAttachmentMessage(file, attachmentFileName, inputFileName)
    when "opus" then
      processAudioAttachmentMessage(file, attachmentFileName, inputFileName)
    else
      processGenericAttachmentMessage(file, attachmentFileName, inputFileName)
  end
end

#
# Process a user message.
#

def processUserMessage(file, message)
  msgClass = getMsgClass(message)
  file.puts("<div class=\"overflow\">")
  file.puts("<div class=\"#{msgClass} userMessage\">")

  printSenderId(file, message)

  if !message["attachment"]
    processRegularUserMessage(file, message)
  else
    processAttachmentMessage(file, message)
  end

  file.puts("<div class=\"timestamp\">")
  file.puts(message["timestamp"].strftime("%H:%M"))
  file.puts("</div>")
  file.puts("</div>")
  file.puts("</div>")
end

#
# Process a system message.
#

def processSystemMessage(file, message)
  file.puts("<div class=\"systemMessage\">")
  file.puts("<p align=\"center\">")
  file.puts(uniToHtml(message["text"]))
  file.puts("</p>")
  file.puts("</div>")
end

#
# Process a message.
#

def processMessage(file, message)
  if message["senderId"]
    processUserMessage(file, message)
  else
    processSystemMessage(file, message)
  end
end

#
# Copy style sheet file to output directory.
#

scriptFileName = Pathname.new($0)
scriptDirectory = scriptFileName.dirname
cssBaseName = "c2h.css"
IO.copy_stream(scriptDirectory.join(cssBaseName), $outputDir.join(cssBaseName))

#
# Generate HTML.
#

class HtmlOutputFile
  def initialize(name)
    @fileName = $outputDir.join(name)
    @file = File.open(@fileName, "w")
    printHtmlHeader()
  end
  def get()
    return @file
  end
  def close()
    printHtmlFooter()
    @file.close()
  end
  def puts(str)
    @file.puts(str)
  end
  def printHtmlHeader()
    if $options.title
      htmlTitle = uniToHtml($options.title)
    end
    puts("<!DOCTYPE html>")
    puts("<html>")
    puts("<head>")
    if $options.title
      puts("<title>#{htmlTitle}</title>")
    end
    puts("<link rel=\"stylesheet\" href=\"c2h.css\">")
    puts("</head>")
    puts("<body>")
    if $options.title
      puts("<h1>#{htmlTitle}</h1>")
    end
  end
  def printHtmlFooter()
    puts("</body>")
    puts("</html>")
  end
end

indexHtmlFileName = "index.html"
indexHtmlFile = HtmlOutputFile.new(indexHtmlFileName)

currentDay = nil
currentMonth = nil
currentYear = nil

yearFile = nil
monthFile = nil
dayFile = nil

if $options.indexByYear
  indexHtmlFile.puts("<ul>")
elsif $options.indexByMonth
  indexHtmlFile.puts("<dl>")
end

activeFile = indexHtmlFile

$allDays.each_index { |dayIndex|
  today = $allDays[dayIndex]
  timestamp = Date.strptime(today, "%Y-%m-%d")
  messageYear = timestamp.strftime("%Y")
  messageMonth = timestamp.strftime("%Y-%m")
  messageDay = timestamp.strftime("%Y-%m-%d")

  if $options.indexByYear
    if messageYear != currentYear
      if yearFile
        yearFile.close()
      end
      yearFileName = "#{messageYear}.html"
      yearFile = HtmlOutputFile.new(yearFileName)
      yearString = formatYear(timestamp)
      indexHtmlFile.puts("<li><a href=\"#{yearFileName}\">#{yearString}</a>")
      activeFile = yearFile
      currentYear = messageYear
    end
  elsif $options.indexByMonth
    if messageMonth != currentMonth
      if monthFile
        monthFile.close()
      end
      monthFileName = "#{messageMonth}.html"
      monthFile = HtmlOutputFile.new(monthFileName)
      monthString = formatMonth(timestamp)
      if messageYear != currentYear
        indexHtmlFile.puts("<dt> #{messageYear}")
        currentYear = messageYear
      end
      indexHtmlFile.puts("<dd><a href=\"#{monthFileName}\">#{monthString}</a></dd>")
      activeFile = monthFile
      currentMonth = messageMonth
    end
  end

  activeFile.puts("<hr>")
  activeFile.puts("<div class=\"date\">")
  activeFile.puts(formatDay(timestamp))
  activeFile.puts("</div>")
  activeFile.puts("<hr>")

  messages[today].each { |message| processMessage(activeFile.get(), message) }
}

if yearFile
  yearFile.close()
end

if monthFile
  monthFile.close()
end

if dayFile
  dayFile.close()
end

if $options.indexByYear
  indexHtmlFile.puts("</ul>")
elsif $options.indexByMonth
  indexHtmlFile.puts("</dl>")
end

indexHtmlFile.close()

#
# Copy all used emoji files.
#

if $emojiFiles
  $emojiFiles.each { |fileName, isUsed|
    if isUsed
      emojiBaseName = "#{fileName}.png"
      inputFileName = $emojiDir.join(emojiBaseName)
      outputFileName = $outputDir.join(emojiBaseName)
      IO.copy_stream(inputFileName, outputFileName)
    end
  }
end
