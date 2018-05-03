#! /bin/ruby

require 'optparse'
require 'ostruct'
require 'pathname'
require 'date'

#
# ----------------------------------------------------------------------
# Command line handling.
# ----------------------------------------------------------------------
#

class CmdLine
  def self.parse(args)
    options = OpenStruct.new
    options.input = []
    options.outputDirectory = ""
    options.title = nil
    options.me = nil
    options.senderIdMap = {}
    options.verbose = 0
    options.indexByMonth = false
    options.indexByYear = false
    options.emojiDir = nil
    options.imageWidth = 320
    options.imageHeigth = 240
    options.emojiWidth = 20
    options.emojiHeight = 20

    opt_parser = OptionParser.new do |opts|
      opts.banner = "Usage: c2h.rb [options]"
      opts.on("-i", "--input=File/Dir", "Zip file or directory containing _chat.txt.") do |i|
        options.input << i
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
      opts.on("-x", "--indexBy=[month,year]", "Create monthly or annual index.") do |x|
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
      opts.on("--imageSize=<width>x<height>", "Limit size of embedded images, default 320x240.") do |s|
        sa = s.split("x")
        options.imageWidth = sa[0].to_i
        options.imageHeight = sa[1].to_i
      end
      opts.on("--emojiSize=<width>x<height>", "Size of inline emoji images, default 20x20.") do |s|
        sa = s.split("x")
        options.emojiWidth = sa[0].to_i
        options.emojiHeight = sa[1].to_i
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

if $options.input.empty? or $options.outputDirectory.empty?
  CmdLine.parse(["-h"]) # exits
end

#
# ----------------------------------------------------------------------
# Input file parsing.
# ----------------------------------------------------------------------
#

class InputFileParser
  def initialize(input)
    openAndReadInput(input)
  end

  def openAndReadInput(input)
    #
    # Read chat file in binary so that ruby does not touch line endings.
    #

    if input.directory?
      @inputType = "dir"
      @inputDir = input
      chatTxtFileName = input.join("_chat.txt")

      if !chatTxtFileName.readable?
        puts "Oops: \"" + chatTxtFileName.to_s + "\" does not exist or is not readable."
        exit
      end

      chatTxtFile = File.open(chatTxtFileName, "rb")
      chatTxt = chatTxtFile.read
      chatTxtFile.close
    elsif input.extname == ".zip"
      require 'zip'
      @inputType = "zip"
      @zipFile = Zip::File.open(input)
      chatTxt = @zipFile.read("_chat.txt")
    else
      puts "Oops: Unable to read input \"" + input.to_s + "\", must be directory or ZIP file."
      exit
    end

    parseMessages chatTxt

    if @inputType == ".zip"
      @zipFile.close()
    end
  end

  def parseMessages(chatTxt)
    #
    # Message lines are separated by CR LF.
    #
    chatTxt.split("\r\n").each { |messageLine|
      #
      # Force message to UTF-8 after reading the file in binary.
      #

      parseMessage messageLine.force_encoding("UTF-8")
    }
  end

  def parseMessage(messageLine)
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
    # description, it is not exported -- this is a deficiency of the WhatsApp
    # export feature.
    #

    if attachmentMatch = message.match('([0-9A-Za-z\- ]+\.[A-Za-z0-9]+).*<[^\s>]+>')
      message = nil
      attachmentFileName = attachmentMatch[1]
      copyAttachment(attachmentFileName)
    else
      attachmentFileName = nil
    end

    message = {
      "timestamp" => timestamp,
      "senderId" => senderId,
      "text" => message,
      "attachment" => attachmentFileName
    }

    recordMessage message
  end

  def recordMessage(message)
    timestamp=message["timestamp"]

    year=timestamp.strftime("%Y")
    month=timestamp.strftime("%Y-%m")
    day=timestamp.strftime("%Y-%m-%d")
    sec=timestamp.strftime("%H:%M:%S")

    $allYears[year] = true
    $allMonths[month] = true

    #
    # Check for and avoid duplicates.
    #

    if !$messages.include?(day)
      $messages[day] = Hash.new
    end

    if !$messages[day].include?(sec)
      $messages[day][sec] = Array.new
    end

    if !$messages[day][sec].include?(message)
      $messages[day][sec] << message
    end

    #
    # Index sender ids.
    #

    senderId = message["senderId"]
    if senderId and !$senderIds.include?(senderId)
      $senderIds[senderId] = true
    end

    #
    # Count messages.
    #

    $messageCount = $messageCount + 1
  end

  def copyAttachment(attachmentFileName)
    outputFileName = $outputDir.join(attachmentFileName)

    if outputFileName.exist?
      outputFileName.delete()
    end

    case (@inputType)
    when "dir" then
      inputFileName = @inputDir.join(attachmentFileName)
      IO.copy_stream(inputFileName, outputFileName)
    when "zip" then
      @zipFile.extract(attachmentFileName, outputFileName)
    end
  end
end

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
# Output generation helpers.
# ----------------------------------------------------------------------
#

#
# Format a date string "January 1, 2018".
#

def formatDay(date)
  return date.strftime("%B %-d, %Y")
end

def formatMonthAndYear(date)
  return date.strftime("%B %Y")
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
  lastEmojiWasText = true
  while i = messageText.index('&')
    if i != 0
      output.concat(messageText[0..i-1])
    end
    codepoints, remainder = eatConsecutiveUnicode(messageText[i..-1])
    codepoints.delete_if { |cp| (cp >= 65024)  and (cp <= 65039)  } # Delete variation selectors.

    while codepoints.length > 0
      hexCodepoints = codepoints.map { |cp| sprintf("%x",cp) }      # Map to hexadecimal.
      subLength = findLongestUnicodeEmojiSubsequence(hexCodepoints)
      if subLength > 0
        basename=hexCodepoints[0..subLength-1].join("_")
        output.concat("<img width=\"#{$options.emojiWidth}\" height=\"#{$options.emojiHeight}\" src=\"emoji_u#{basename}#{$emojiExt}\">")
        codepoints = codepoints[subLength..-1]
        $emojiFiles[basename] = true
        lastEmojiWasText = false
      else
        cp0 = codepoints[0]
        if cp0 < 127995 or cp0 > 127999
          printUnicode = true
          lastEmojiWasText = true
        else
          #
          # Print skin tone modifier only if the preceding emoji was printed as
          # unicode text, so that the browser may choose the correct image for
          # this skin tone. If the preceding emoji was rendered as an image, then
          # the emoji image set does not include different images for different
          # skin tones; in this case, do not print the skin tone modifier as it
          # would be useless.
          #

          printUnicode = lastEmojiWasText
          lastEmojiWasText = false
        end
        if printUnicode
          output.concat(sprintf("&#%d;", cp0))
        end
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
  senderIdToUse = message["senderId"]
  if $options.senderIdMap.include?(senderIdToUse)
    senderIdToUse = $options.senderIdMap[senderIdToUse]
  end
  return senderIdToUse == $options.me
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

  noSenderId = (($mappedSenderIds.size == 2) or isMyMessage(message))

  if !noSenderId
    file.puts("<span class=\"senderId\">" + uniToHtml(senderIdToPrint) + "</span> ")
  end
end

#
# Scale image.
#

def scaleImage(width, height)
  if width > $options.imageWidth or height > $options.imageHeigth
    widthScale = width.to_f / $options.imageWidth.to_f
    heightScale = height.to_f / $options.imageHeigth.to_f
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
  attachmentFileNameAsString = attachmentFileName.to_s
  file.puts("<audio controls=\"\">")
  file.puts("<source src=\"#{attachmentFileNameAsString}\">")
  file.puts("<a href=\"#{attachmentFileNameAsString}\">#{attachmentFileNameAsString}</a>")
  file.puts("</audio>")
end

#
# Process a message that is an audio attachment.
#

def processVideoAttachmentMessage(file, attachmentFileName, inputFileName)
  attachmentFileNameAsString = attachmentFileName.to_s
  file.puts("<video width=\"#{$options.imageWidth}\" controls=\"\">")
  file.puts("<source src=\"#{attachmentFileNameAsString}\">")
  file.puts("<a href=\"#{attachmentFileNameAsString}\">#{attachmentFileNameAsString}</a>")
  file.puts("</video>")
end

#
# Process a generic attachment (e.g., a PDF file).
#

def processGenericAttachmentMessage(file, attachmentFileName, inputFileName)
  attachmentFileNameAsString = attachmentFileName.to_s
  file.puts("<a href=\"#{attachmentFileNameAsString}\">#{attachmentFileNameAsString}</a>")
end

#
# Process a message that is an attachment.
#

def processAttachmentMessage(file, message)
  attachmentFileName = Pathname.new(message["attachment"])
  attachmentFileType = attachmentFileName.extname[1..-1]
  inputFileName = $outputDir.join(attachmentFileName)

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
  file.puts(formatMessageText(message["text"]))
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
    puts("<!DOCTYPE html>")
    puts("<html>")
    puts("<head>")
    if $options.title
      htmlTitle = uniToHtml($options.title)
      puts("<title>#{htmlTitle}</title>")
    end
    puts("<link rel=\"stylesheet\" href=\"c2h.css\">")
    puts("</head>")
    puts("<body>")
  end
  def printHtmlFooter()
    puts("</body>")
    puts("</html>")
  end
end

#
# ----------------------------------------------------------------------
# Main.
# ----------------------------------------------------------------------
#

#
# Create output directory if it does not exist.
#

$outputDir = Pathname.new($options.outputDirectory)

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

$pngEmoji = false
$svgEmoji = false
$emojiFiles = Hash.new

if $options.emojiDir
  $emojiDir = Pathname.new($options.emojiDir)
  Dir.entries($emojiDir).each { |fileName|
    if fileName[0..6] == "emoji_u"
      ext=fileName[-4..-1]
      imageBaseName=fileName[7..-5]
      if ext == ".png"
        $pngEmoji = true
      elsif ext == ".svg"
        $svgEmoji = true
      else
        puts "Oops: Emoji file \"" + fileName + "\" is neither PNG nor SVG."
        exit 1
      end
      $emojiFiles[imageBaseName] = false
    end
  }
end

if $pngEmoji and $svgEmoji
  puts "Oops: Both PNG and SVG emoji found."
  exit 1
end

if $pngEmoji
  $emojiExt = ".png"
else
  $emojiExt = ".svg"
end

#
# Read input files.
#

#
# messages is a hash "year-month-day" -> dailyMessages
# dailyMessages is a hash "hour-minute-second" -> setOfMessages
# setOfMessages is an array
#

$messageCount = 0
$messages = Hash.new
$senderIds = Hash.new
$allYears = Hash.new
$allMonths = Hash.new

$options.input.each { | inputFileOrDir|
  InputFileParser.new(Pathname.new(inputFileOrDir))
}

#
# Cleanse sender ids for "me" and "map".
#

$mappedSenderIds = {}

$senderIds.each_key { |senderId|
  mappedSenderId = senderId
  $options.senderIdMap.keys.each { |key|
    if senderId.include?(key)
      mappedSenderId = $options.senderIdMap[key]
    end
  }

  $options.senderIdMap[senderId] = mappedSenderId
  $mappedSenderIds[mappedSenderId] = true
}

#
# If there are only two sender ids, and the "me" option was not given,
# choose one of them as "me."
#

if $mappedSenderIds.size == 2 and $options.me == nil
  $options.me = $senderIds.keys[0]
end

#
# Get arrays of all years, months, days.
#

$allYears = $allYears.keys.sort
$allMonths = $allMonths.keys.sort
$allDays = $messages.keys.sort

#
# Copy style sheet file to output directory.
#

scriptFileName = Pathname.new($0)
scriptDirectory = scriptFileName.dirname
cssBaseName = "c2h.css"
IO.copy_stream(scriptDirectory.join(cssBaseName), $outputDir.join(cssBaseName))

#
# Start HTML generation.
#

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

if $options.title and ($options.indexByYear or $options.indexByMonth)
  htmlTitle = uniToHtml($options.title)
  indexHtmlFile.puts("<h1>#{htmlTitle}</h1>")
end

activeFile = indexHtmlFile

$allDays.each_index { |dayIndex|
  today = $allDays[dayIndex]
  timestamp = Date.strptime(today, "%Y-%m-%d")
  messageYear = timestamp.strftime("%Y")
  messageMonth = timestamp.strftime("%Y-%m")
  messageDay = timestamp.strftime("%Y-%m-%d")

  activeFile.puts("<hr>")

  if $options.indexByYear
    yearFileName = "#{messageYear}.html"
    if messageYear != currentYear
      if yearFile
        yearFile.close()
      end
      yearFile = HtmlOutputFile.new(yearFileName)
      yearString = formatYear(timestamp)
      indexHtmlFile.puts("<li><a href=\"#{yearFileName}\">#{yearString}</a>")
      activeFile = yearFile
      currentYear = messageYear
    end
    if messageMonth != currentMonth
      monthName = formatMonth(timestamp)
      activeFile.puts("<h1 id=\"#{messageMonth}\">#{monthName}</h1>")
      indexHtmlFile.puts("<a href=\"#{yearFileName}##{messageMonth}\">#{monthName}</a>")
      currentMonth = messageMonth
    end
    activeFile.puts("<h2 id=\"#{messageDay}\">#{formatDay(timestamp)}</h2>")
  elsif $options.indexByMonth
    monthFileName = "#{messageMonth}.html"
    if messageMonth != currentMonth
      if monthFile
        monthFile.close()
      end
      monthFile = HtmlOutputFile.new(monthFileName)
      monthString = formatMonth(timestamp)
      indexHtmlFile.puts("</dd>")
      if messageYear != currentYear
        indexHtmlFile.puts("<dt> #{messageYear}")
        currentYear = messageYear
      end
      indexHtmlFile.puts("<dd><a href=\"#{monthFileName}\">#{monthString}</a>")
      activeFile = monthFile
      currentMonth = messageMonth
    end
    dayOnly = timestamp.strftime("%d")
    activeFile.puts("<h1 id=\"#{messageDay}\">#{formatDay(timestamp)}</h1>")
    indexHtmlFile.puts("<a href=\"#{monthFileName}##{messageDay}\">#{dayOnly}</a>")
  else
    if messageYear != currentYear
      activeFile.puts("<h1 id=\"#{messageYear}\">#{messageYear}</h1>")
      currentYear = messageYear
    end
    if messageMonth != currentMonth
      monthName = formatMonth(timestamp)
      activeFile.puts("<h2 id=\"#{messageMonth}\">#{monthName}</h2>")
      currentMonth = messageMonth
    end
    activeFile.puts("<h3 id=\"#{messageDay}\">#{formatDay(timestamp)}</h3>")
  end

  activeFile.puts("<hr>")

  dailyMessages = $messages[today]
  dailyTimestamps = dailyMessages.keys.sort
  dailyTimestamps.each { |timestamp|
    dailyMessages[timestamp].each { |message| processMessage(activeFile.get(), message) }
  }
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
  indexHtmlFile.puts("</dd>")
  indexHtmlFile.puts("</dl>")
end

indexHtmlFile.close()

#
# Copy all used emoji files.
#

if $emojiFiles
  $emojiFiles.each { |fileName, isUsed|
    if isUsed
      emojiBaseName = "emoji_u#{fileName}#{$emojiExt}"
      inputFileName = $emojiDir.join(emojiBaseName)
      outputFileName = $outputDir.join(emojiBaseName)
      IO.copy_stream(inputFileName, outputFileName)
    end
  }
end
