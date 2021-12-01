module WhatsAppChatBeautifier
  #
  # ----------------------------------------------------------------------
  # Parser for chat files exported from Whats App.
  # ----------------------------------------------------------------------
  #

  class WhatsAppParser
    def initialize(me = nil)
      @me = me
      @messages = Array.new
    end

    def getMe()
      return @me
    end

    def getMessages()
      return @messages
    end

    def load(chatTxt, from=nil, to=nil)
      #
      # Message lines are separated by CR LF.
      #

      chatTxt.split("\r\n").each { |messageLine|
        message = parseMessage(messageLine)
        next if from and message[:timestamp].to_date < from
        next if to and message[:timestamp].to_date > to
        @messages << message
      }
    end

    def parseMessage(messageLine)
      #
      # Message line starts with a "date, time:", sometimes preceded by a
      # unicode character.
      #

      timestampMatch = messageLine.match('(\[)?(\d{1,2}.\d{1,2}.\d{1,2}, \d{1,2}:\d{1,2}:\d{1,2})(\])?(:)?')
      raise "Line does not start with a timestamp: \"#{messageLine}\"" if timestampMatch == nil

      timestamp = DateTime.strptime(timestampMatch[2].strip
                                      .gsub(/\//, { '/' => '.' }),
                                    "%d.%m.%y, %H:%M:%S")

      #
      # After the timestamp, there is usually the sender ID followed by a ":",
      # except for system messages. Assumption: system messages never contain
      # a ":".
      #

      endOfTimestamp = timestampMatch.end(2)
      endOfSenderId = messageLine.index(":", endOfTimestamp + 1)

      if endOfSenderId
        sender = messageLine[endOfTimestamp+1..endOfSenderId-1].strip
        message = messageLine[endOfSenderId+1..-1].strip
        if @me and sender.include?(@me)
          type = :Sent
          sender = nil
        else
          type = :Received
        end
      else
        type = :System
        sender = nil
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

      for attachmentRegex in ['([0-9A-Za-z\- ]+\.[A-Za-z0-9]+).*<[^\s>]+>',
                              '<attached: (\S+)>'] do
        attachmentMatch = message.match(attachmentRegex)

        if attachmentMatch != nil
          message = nil
          attachmentFileName = attachmentMatch[1]
          break
        else
          attachmentFileName = nil
        end
      end

      return {
        :timestamp => timestamp,
        :type => type,
        :sender => sender,
        :message => message,
        :attachment => attachmentFileName
      }
    end
  end
end
