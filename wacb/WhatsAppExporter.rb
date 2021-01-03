module WhatsAppChatBeautifier
  #
  # ----------------------------------------------------------------------
  # Exporter to WhatsApp
  # ----------------------------------------------------------------------
  #

  class WhatsAppExporter
    def initialize(outputDir, messages, options=nil)
      setDefaultOptions(options)
      @messages = messages
      @outputDir = outputDir
      @numAttachments = 0
      @attachmentCounter = 0
      @attachmentMap = Hash.new
    end

    def setDefaultOptions(options)
      @options = options ? options : Hash.new
      setDefaultOption(:me, "Me")
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
      allMessages = @messages.getMessages()
      @options[:log].begin("Writing #{allMessages.size()} messages to \"_chat.txt\"")
      chatTxt = messages2chat(allMessages)
      chatTxt.force_encoding("UTF-8")
      chatFileName = @outputDir.join("_chat.txt")
      IO.binwrite(chatFileName, chatTxt)
      @options[:log].end()
      exportAttachments(allMessages) if @options[:attachments]
    end

    def messages2chat(messages)
      chatTxt = ""

      messages.each { |message|
        if message[:message] or message[:attachment]
          chatTxt << message2chat(message) << "\r\n"
        end
      }

      return chatTxt
    end

    def message2chat(message)
      timestamp = message[:timestamp].strftime("%d.%m.%y, %H:%M:%S ")

      line = timestamp
      case (message[:type])
      when :Sent
        line << @options[:me] << ": "
      when :Received
        line << message[:sender] << ": "
      when :System
      when :Deleted
      else
        raise "Oops"
      end

      raise "Oops at " + timestamp if message[:message] and message[:attachment]
      raise "Oops at " + timestamp if !message[:message] and !message[:attachment]

      if message[:message]
        line << message[:message].gsub("\r\n", "\n")
      else
        @numAttachments = @numAttachments + 1
        inputFileName = Pathname.new(message[:attachment])
        outputFileName = mapAttachmentName(message)
        line << outputFileName.to_s << " <attached>"
      end

      return line
    end

    def mapAttachmentName(message)
      attachmentName = message[:attachment]

      if @options[:renameAttachments]
        outputFileName = message[:timestamp].strftime("%Y-%m-%d")
        outputFileName << "-%05d" % @numAttachments
        outputFileName << Pathname.new(attachmentName).extname
      else
        outputFileName = Pathname.new(attachmentName).basename
      end

      @attachmentMap[attachmentName] = outputFileName
    end

    def exportAttachments(messages)
      messages.each { |message|
        if message[:attachment]
          exportAttachment(message)
        end
      }
    end

    def exportAttachment(message)
      attachmentName = message[:attachment]
      outputFileName = @attachmentMap[attachmentName]
      outputPath = @outputDir.join(outputFileName)

      @attachmentCounter = @attachmentCounter + 1
      info = @options[:attachments] == :Copy ? "Copying" : "Moving"
      info << " attachment " << @attachmentCounter.to_s << " / " << @numAttachments.to_s
      info << ", " << Pathname.new(attachmentName).basename.to_s
      @options[:log].begin(info)

      if @options[:attachments] == :Copy
        message[:inputFile].copyAttachment(attachmentName, outputPath)
      elsif @options[:attachments] == :Move
        message[:inputFile].moveAttachment(attachmentName, outputPath)
      else
        raise "Oops"
      end

      @options[:log].end()
    end
  end
end
