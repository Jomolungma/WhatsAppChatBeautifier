module WhatsAppChatBeautifier
  #
  # ----------------------------------------------------------------------
  # Media file helpers.
  # ----------------------------------------------------------------------
  #

  def WhatsAppChatBeautifier.pngSize(file)
    file.rewind()
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

  def WhatsAppChatBeautifier.jpgSize(file)
    file.rewind()
    jpgSig = [255, 216, 255, 224].pack("C*")
    fileSig = file.read(4)
    if jpgSig == fileSig
      app0Length = file.read(2).unpack("n")[0]
      app0Id = file.read(4)
      if app0Id == "JFIF"
        if file.is_a?(File)
          file.seek(app0Length - 6, IO::SEEK_CUR)
        else
          file.read(app0Length - 6) ; # read and discard
        end
        while !file.eof?
          segMarker = file.read(2).unpack("C*")
          segLength = file.read(2).unpack("n")[0]
          if segMarker[0] == 255 and segMarker[1] == 192
            sof0Info = file.read(5).unpack("Cnn")
            return ["JPG", sof0Info[2], sof0Info[1]]
          end
          if file.is_a?(File)
            file.seek(segLength - 2, IO::SEEK_CUR)
          else
            file.read(segLength - 2) ; # read and discard
          end
        end
      end
    end
    return [nil, 0, 0]
  end

  def WhatsAppChatBeautifier.imageSize(stream)
    begin
      imgFile, width, height = pngSize(stream)

      if !imgFile
        imgFile, width, height = jpgSize(stream)
      end

      return [imgFile, width, height]
    rescue Exception
      return nil
    end
  end

  #
  # Helper class to replace emojis with inline images.
  #

  class EmojiHelper
    def initialize(emojiDir = nil)
      @emojiFiles = Set.new
      @usedEmojis = Set.new
      @emojiExt = nil

      if emojiDir
        @emojiDir = Pathname.new(emojiDir)
        scanEmojiFiles
      else
        @emojiDir = nil
      end
    end

    #
    # Scan list of available emoji files.
    #

    def scanEmojiFiles()
      Dir.entries(@emojiDir).each { |fileName|
        if fileName[0..6] == "emoji_u"
          ext=fileName[-4..-1]
          imageBaseName=fileName[7..-5]
          if ext != ".png" and ext != ".svg"
            raise "Oops: Emoji file \"" + fileName + "\" is neither PNG nor SVG."
          end
          if @emojiExt == nil
            @emojiExt = ext
          end
          if ext != @emojiExt
            raise "Oops: Both PNG and SVG emoji found."
          end
          @emojiFiles.add(imageBaseName)
        end
      }
    end

    #
    # Get count of used/available emoji files.
    #

    def getCount()
      available = @emojiFiles.size()
      used = @usedEmojis.size()
      return available, used
    end

    #
    # Copy all used emoji files to output directory.
    #

    def copyUsedEmojiFiles(outputDir)
      @usedEmojis.each { |emoji|
        emojiBaseName = "emoji_u#{emoji}#{@emojiExt}"
        inputFileName = @emojiDir.join(emojiBaseName)
        outputFileName = outputDir.join(emojiBaseName)
        IO.copy_stream(inputFileName, outputFileName)
      }
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
        if @emojiFiles.include?(basename)
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
      haveRegularText = false

      while match = messageText.match("&#[0-9]+;")
        s = match.begin(0)
        if s != 0
          output << messageText[0..s-1]
          messageText = messageText[s..-1]
          haveRegularText = true
        end

        codepoints, remainder = eatConsecutiveUnicode(messageText)
        codepoints.delete_if { |cp| (cp >= 65024)  and (cp <= 65039)  } # Delete variation selectors.

        # After uniToHtml, there should not be any stray ampersands.
        raise "Oops: \"#{messageText[i..-1]}\"" if codepoints.length == 0

        while codepoints.length > 0
          hexCodepoints = codepoints.map { |cp| sprintf("%x",cp) }      # Map to hexadecimal.
          subLength = findLongestUnicodeEmojiSubsequence(hexCodepoints)

          if subLength > 0
            basename=hexCodepoints[0..subLength-1].join("_")
            output << "<img class=\"{placeholder}\" src=\"emoji_u#{basename}#{@emojiExt}\">"
            codepoints = codepoints[subLength..-1]
            @usedEmojis.add(basename)
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
              output << sprintf("&#%d;", cp0)
            end
            codepoints = codepoints[1..-1]
          end
        end

        messageText = remainder
      end

      output << messageText

      if haveRegularText
        output.gsub!("{placeholder}", "inlineEmoji")
      else
        output.gsub!("{placeholder}", "standaloneEmoji")
      end

      return output
    end
  end

  #
  # ----------------------------------------------------------------------
  # HTML output helper class.
  # ----------------------------------------------------------------------
  #

  class HtmlOutputFile
    def initialize(fileName, title = nil)
      @fileName = fileName
      @file = File.open(@fileName, "w")
      @title = title
      @attachmentIndex = 0
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
      if @title
        puts("<title>#{@title}</title>")
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
  # Exporter to HTML
  # ----------------------------------------------------------------------
  #

  class HtmlExporter
    @@cssBaseName = "c2h.css"

    def initialize(outputDir, messages, options)
      require 'uri'
      setDefaultOptions(options)
      @messages = messages
      @outputDir = outputDir
      @numAttachments = 0
      @attachmentCounter = 0
      @emojiHelper = EmojiHelper.new(@options[:emojiDir])
      @senderIds = @messages.getSenders
    end

    def setDefaultOptions(options)
      @options = options ? options : Hash.new
      setDefaultOption(:me, nil)
      setDefaultOption(:title, nil)
      setDefaultOption(:backgroundImage, nil)
      setDefaultOption(:split, nil)
      setDefaultOption(:emojiDir, nil)
      setDefaultOption(:imageWidth, 320)
      setDefaultOption(:imageHeight, 240)
      setDefaultOption(:attachments, nil)
      setDefaultOption(:renameAttachments, false)
      setDefaultOption(:log, LogOutput.new())
    end

    def setDefaultOption(option, value)
      if !@options.include?(option) or @options[option] == nil
        @options[option] = value
      end
    end

    def export()
      if !@options[:split]
        exportCompleteFile()
      elsif @options[:split] == :Month
        exportIndex()
        exportMonthlyFiles()
      elsif @options[:split] == :Year
        exportIndex()
        exportAnnualFiles()
      end

      #
      # Copy style sheet file to output directory.
      #

      copyStyleSheet()

      #
      # Copy background image chosen by the user.
      #

      if @options[:backgroundImage]
        @options[:log].begin("Copying background image from \"#{@options[:backgroundImage]}\"")
        backgroundFileName = Pathname.new(@options[:backgroundImage])
        backgroundBaseName = backgroundFileName.basename
        outputFileName = @outputDir.join(backgroundBaseName)
        IO.copy_stream(backgroundFileName, outputFileName)
        @options[:log].end()
      end

      #
      # Copy all used emojis.
      #

      available, used = @emojiHelper.getCount()
      if used > 0
        @options[:log].begin("Copying #{used} used emoji files")
        @emojiHelper.copyUsedEmojiFiles(@outputDir)
        @options[:log].end()
      end
    end

    #
    # Copy the style sheet to the output directory.
    #

    def copyStyleSheet()
      scriptFileName = Pathname.new($0)
      scriptDirectory = scriptFileName.dirname
      cssInputFileName = scriptDirectory.join(@@cssBaseName)
      cssOutputFileName = @outputDir.join(@@cssBaseName)
      @options[:log].begin("Copying style sheet \"#{cssInputFileName.to_s}\"")
      cssInputFile = File.open(cssInputFileName, "r:UTF-8")
      css = cssInputFile.read()
      cssInputFile.close()

      [:imageWidth, :imageHeight, :backgroundImage].each { |key|
        stringToReplace = "\#\{" << key.to_s << "\}"
        if key == :backgroundImage
          if @options[:backgroundImage]
            url = Pathname.new(@options[:backgroundImage]).basename
            value = "background-image: url(\"#{url}\");"
          else
            value = ""
          end
        else
          value = @options[key].to_s
        end
        css.gsub!(stringToReplace, value)
      }

      cssOutputFile = File.open(cssOutputFileName, "w:UTF-8")
      cssOutputFile.write(css)
      cssOutputFile.close()
      @options[:log].end()
    end

    #
    # Create an index.html file for annual or monthly files.
    #

    def exportIndex()
      indexFileName = @outputDir.join("index.html")
      indexFile = HtmlOutputFile.new(indexFileName, @options[:title])
      @options[:log].begin("Exporting index to \"#{indexFileName.to_s}\"")

      if @options[:title]
        htmlTitle = uniToHtml(@options[:title])
        indexFile.puts("<h1>#{htmlTitle}</h1>")
      end

      years = @messages.getYears()
      years.each { |year|
        if @options[:split] == :Year
          indexFile.puts("<h1><a href=\"#{year}.html\">#{year}</a></h1>")
        else
          indexFile.puts("<h1>#{year}</h1>")
        end

        indexFile.puts("<dl>")

        months = @messages.getMonths(year)
        months.each { |month|
          timestamp = Date.strptime(month, "%Y-%m")
          monthName = formatMonthAndYear(timestamp)

          if @options[:split] == :Year
            refFileName="#{year}.html"
          else
            refFileName="#{month}.html"
          end

          indexFile.puts("<dt>")
          indexFile.puts("<a href=\"#{refFileName}##{month}\">#{monthName}</a>")
          indexFile.puts("<dd>")

          days = @messages.getDays(month)
          days.each { |day|
            indexFile.puts("<a href=\"#{refFileName}##{day}\">#{day[8,2]}</a>")
          }
        }

        indexFile.puts("</dl>")
      }

      indexFile.close()
      @options[:log].end()
    end

    #
    # Export a complete file.
    #

    def exportCompleteFile()
      completeFileName = @outputDir.join("index.html")
      completeFile = HtmlOutputFile.new(completeFileName, @options[:title])
      @options[:log].begin("Exporting chat to \"#{completeFileName.to_s}\"")

      if @options[:title]
        htmlTitle = uniToHtml(@options[:title])
        completeFile.puts("<h1>#{htmlTitle}</h1>")
      end

      years = @messages.getYears()
      years.each { |year|
        exportAnnualContent(completeFile, year)
      }

      completeFile.close()
      @options[:log].end()
    end

    #
    # Export all annual files.
    #

    def exportAnnualFiles()
      years = @messages.getYears()
      years.each { |year|
        exportAnnualFile(year)
      }
    end

    #
    # Export an annual file.
    #

    def exportAnnualFile(year)
      annualFileName = @outputDir.join("#{year}.html")
      annualFile = HtmlOutputFile.new(annualFileName, @options[:title])
      @options[:log].begin("Exporting messages from #{year} to \"#{annualFileName.to_s}\"")
      exportAnnualContent(annualFile, year)
      annualFile.close()
      @options[:log].end()
    end

    #
    # Export annual content.
    #

    def exportAnnualContent(file, year)
      file.puts("<h1 id=\"#{year}\">#{year}</h1>")
      months = @messages.getMonths(year)
      months.each { |month|
        exportMonthlyContent(file, month)
      }
    end

    #
    # Export all monthly files.
    #

    def exportMonthlyFiles()
      months = @messages.getMonths()
      months.each { |month|
        exportMonthlyFile(month)
      }
    end

    #
    # Export a monthly file.
    #

    def exportMonthlyFile(month)
      monthFileName = @outputDir.join("#{month}.html")
      monthFile = HtmlOutputFile.new(monthFileName, @options[:title])
      @options[:log].begin("Exporting messages from #{month} to \"#{monthFileName.to_s}\"")
      exportMonthlyContent(monthFile, month)
      monthFile.close()
      @options[:log].end()
    end

    #
    # Export monthly content.
    #

    def exportMonthlyContent(file, month)
      timestamp = Date.strptime(month, "%Y-%m")
      monthName = formatMonthAndYear(timestamp)
      file.puts("<h2 id=\"#{month}\">#{monthName}</h2>")

      days = @messages.getDays(month)

      days.each { |day|
        timestamp = Date.strptime(day, "%Y-%m-%d")
        messageYear = timestamp.strftime("%Y")
        messageMonth = timestamp.strftime("%Y-%m")

        file.puts("<hr>")
        file.puts("<h3 id=\"#{day}\">#{formatDay(timestamp)}</h3>")
        file.puts("<hr>")

        dailyTimestamps = @messages.getTimes(day)
        dailyTimestamps.each { |time|
          messages = @messages.getMessages(day, time)
          messages.each { |message|
            html = processMessage(message)
            file.puts(html)
          }
        }
      }
    end

    #
    # Date formatting helpers.
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
      html.gsub!("\n", "<br>")
      return html
    end

    #
    # Format message content.
    # - Replace URLs in a message text with links to that URL.
    # - Encode unicode or unprintable characters with &#<nn>; codepoints.
    # - Replace emojis with inline images if desired.
    #

    def formatMessageText(messageText)
      s = 0
      result = ""
      while urlMatch = messageText.match(URI.regexp, s)
        if urlMatch.begin(0) > s
          result.concat(uniToHtml(messageText[s..urlMatch.begin(0)-1]))
        end
        linkable = ((urlMatch[1] == "http") or (urlMatch[1] == "https"))
        if linkable == true
          result.concat("<a href=\"")
          result.concat(urlMatch[0])
          result.concat("\">")
        end
        result.concat(uniToHtml(urlMatch[0]))
        if linkable
          result.concat("</a>")
        end
        s = urlMatch.end(0)
      end
      result.concat(uniToHtml(messageText[s..-1]))
      return @emojiHelper.replaceEmojisWithImages(result)
    end

    #
    # Is this a message from "me"?
    #

    def isMyMessage(message)
      return message[:type] == :Sent
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

    def printSenderId(message)
      #
      # Do not print sender id if:
      # - There are only two participants to the chat. (In this case, if the
      #   "--me" option was not given, one of them is chosen as "me".)
      # - There are more than two participants to the chat and the message is
      #   mine.
      #

      html = ""
      noSenderId = ((@senderIds.size == 1) or isMyMessage(message))

      if !noSenderId
        senderName = (message[:type] == :Sent) ? @options[:me] : message[:sender]
        if senderName and !senderName.empty?()
          html = "<span class=\"senderName\">" + uniToHtml(message[:sender]) + "</span><br>"
        end
      end

      return html
    end

    #
    # Scale image.
    #

    def scaleImage(width, height)
      if width > @options[:imageWidth] or height > @options[:imageHeight]
        widthScale = width.to_f / @options[:imageWidth].to_f
        heightScale = height.to_f / @options[:imageHeight].to_f
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

    def processRegularUserMessage(message)
      return formatMessageText(message[:message])
    end

    #
    # Process a message that is an image attachment.
    #

    def processImageAttachmentMessage(inputFile, attachmentName, outputFileName)
      #
      # If the "thumbnails" option is given, we check the image size, and scale
      # large images down to our "thumbnail" size.
      #

      begin
        imageStream = inputFile.openAttachment(attachmentName)
        imgFile, imgWidth, imgHeight = WhatsAppChatBeautifier.imageSize(imageStream)
      rescue Exception
        imgFile = nil
      end

      if imgFile == nil
        html = "<img class=\"inlineImage\" src=\"#{outputFileName}\">"
      else
        width, height = scaleImage(imgWidth, imgHeight)
        html = "<a href=\"#{outputFileName}\">\n"
        html << "<img class=\"inlineImage\" width=\"#{width}\" height=\"#{height}\" src=\"#{outputFileName}\">\n"
        html << "</a>\n"
        return html
      end
    end

    #
    # Process a message that is an audio attachment.
    #

    def processAudioAttachmentMessage(attachmentName, outputFileName)
      html = "<audio controls=\"\">\n"
      html << "<source src=\"#{outputFileName}\">\n"
      html << "<a href=\"#{outputFileName}\">#{outputFileName}</a>\n"
      html << "</audio>\n"
      return html
    end

    #
    # Process a message that is an audio attachment.
    #

    def processVideoAttachmentMessage(attachmentName, outputFileName)
      html = "<video controls=\"\">\n"
      html << "<source src=\"#{outputFileName}\">\n"
      html << "<a href=\"#{outputFileName}\">#{outputFileName}</a>\n"
      html << "</video>\n"
      return html
    end

    #
    # Process a generic attachment (e.g., a PDF file).
    #

    def processGenericAttachmentMessage(attachmentName, outputFileName)
      return "<a href=\"#{outputFileName}\">#{outputFileName}</a>\n"
    end

    #
    # Process a message that is an attachment.
    #

    def processAttachmentMessage(message)
      attachmentName = message[:attachment]
      attachmentFileType = Pathname.new(attachmentName).extname

      if @options[:renameAttachments]
        @attachmentCounter = @attachmentCounter + 1
        outputFileName = message[:timestamp].strftime("%Y-%m-%d")
        outputFileName << "-%05d" % @attachmentCounter
        outputFileName << attachmentFileType
      else
        outputFileName = Pathname.new(attachmentName).basename.to_s
      end

      outputPath = @outputDir.join(outputFileName)

      case (attachmentFileType)
      when ".jpg", ".jpeg", ".png", ".thumb" then
        html = processImageAttachmentMessage(message[:inputFile], attachmentName, outputFileName)
      when ".mp4" then
        html = processVideoAttachmentMessage(attachmentName, outputFileName)
      when ".opus", ".mp3", ".3gp", ".m4a" then
        html = processAudioAttachmentMessage(attachmentName, outputFileName)
      else
        html = processGenericAttachmentMessage(attachmentName, outputFileName)
      end

      if @options[:attachments] == :Copy
        message[:inputFile].copyAttachment(attachmentName, outputPath)
      elsif @options[:attachments] == :Move
        message[:inputFile].moveAttachment(attachmentName, outputPath)
      elsif @options[:attachments] != nil
        raise "Oops"
      end

      return html
    end

    #
    # Process a user message.
    #

    def processUserMessage(message)
      msgClass = getMsgClass(message)
      html = "<div class=\"message\">\n"
      html << "<div class=\"#{msgClass} userMessage\">\n"
      html << printSenderId(message)

      if !message[:attachment]
        html << processRegularUserMessage(message)
      else
        html << processAttachmentMessage(message)
      end

      html << "<div class=\"timestamp\">"
      html << message[:timestamp].strftime("%H:%M")
      html << "</div>\n"
      html << "</div>\n"
      html << "</div>\n"
      html << "<p>\n"
      return html
    end

    #
    # Process a system message.
    #

    def processSystemMessage(message)
      html = "<div class=\"message\">"
      html << "<div class=\"systemMessage\">"
      html << formatMessageText(message[:message])
      html << "</div>"
      html << "</div>"
      html << "<p>"
      return html
    end

    #
    # Process a message.
    #

    def processMessage(message)
      if message[:type] == :Sent or message[:type] == :Received
        html = processUserMessage(message)
      else
        html = processSystemMessage(message)
      end
      return html
    end

  end
end
