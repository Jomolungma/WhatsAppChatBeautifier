module WhatsAppChatBeautifier
  #
  # ----------------------------------------------------------------------
  # Parser for chat files exported from Threema.
  # ----------------------------------------------------------------------
  #

  class ThreemaParser
    def initialize(other = nil)
      @other = other ? other : "<<<"
      @messages = Array.new
    end

    def getMe()
      return nil
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

    def nameToMonth(month)
      #
      # Threema timestamps use local month names. Support english and a few
      # other select languages. Use regexps and "." to keep this script file
      # ASCII.
      #

      allMonthNames = {
        "English" => [ "January", "February", "March", "April", "May",  "June",  "July",  "August", "September",  "October", "November",  "December"  ],
        "German"  => [ "Januar",  "Februar",  "M.rz",  "April", "Mai",  "Juni",  "Juli",  "August", "September",  "Oktober", "November",  "Dezember"  ],
        "Spanish" => [ "Enero",   "Febrero",  "Marzo", "Abril", "Mayo", "Junio", "Julio", "Agosto", "Septiembre", "Octubre", "Noviembre", "Diciembre" ],
        "French"  => [ "Janvier", "F.vrier",  "Mars",  "Avril", "Mai",  "Juin",  "Juillet", "Ao.t", "Septembre",  "Octobre", "Novembre",  "D.cembre"  ],
      }
      found = nil
      allMonthNames.each_value { |monthNames|
        foundHere = monthNames.index { |name| month.match(name) != nil }
        found = foundHere + 1 if foundHere != nil
      }
      raise "Oops: Invalid month \"#{month}\"." if found == nil
      return found
    end

    def parseTimestamp(timestampMatch)
      day = timestampMatch[1].to_i
      month = nameToMonth(timestampMatch[2])
      year = timestampMatch[3].to_i
      hour = timestampMatch[4].to_i
      min = timestampMatch[5].to_i
      sec = timestampMatch[6].to_i
      return DateTime.new(year,month,day,hour,min,sec)
    end

    def parseMessage(messageLine)
      #
      # Message line starts with "<<<" for incoming messages, ">>>" for
      # outgoing messages, followed by a timestamp, then ":" and the
      # message.
      #
      # The timestamp looks like "<date> at <time> <timezone>", where
      # date is "<day>. <name-of-month> <year>" and
      # time is "<hour>:<min>:<sec>". The timezone is ignored, all
      # timestamps are recorded in local time, which is appropriate.
      #

      case(messageLine[0..2])
        when '>>>' then type = :Sent
        when '<<<' then type = :Received
        else raise "Oops: Unexpected Threema message."
      end

      sender = type == :Sent ? nil : @other

      timestampMatch=messageLine.match('(\d{1,2}). ([^\s]+) (\d{4}) [^\s]+ (\d{2}):(\d{2}):(\d{2})')
      raise "Oops: Unexpected Threema timestamp." if (timestampMatch == nil) or timestampMatch.begin(0) != 4

      timestamp = parseTimestamp(timestampMatch)
      endOfTimestamp = timestampMatch.end(0)
      endOfPrefix = messageLine.index(":", endOfTimestamp + 1)
      message = messageLine[endOfPrefix+1..-1].strip

      #
      # For attachments, the message looks like "<Type> (<filename>)".
      #

      attachmentMatch = message.match('[^\s]+ \(([a-z0-9]+\.[A-Za-z0-9]+)\)')

      if attachmentMatch != nil
        message = nil
        attachmentFileName = attachmentMatch[1]
      else
        attachmentFileName = nil
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
