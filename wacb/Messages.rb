module WhatsAppChatBeautifier
  #
  # ----------------------------------------------------------------------
  # Message handling with indixes.
  # ----------------------------------------------------------------------
  #

  class Messages
    #
    # messages is a hash "year-month-day" => dailyMessages
    # dailyMessages is a hash "hour:minute:second" => setOfMessages
    # setOfMessages is an array of messages
    # message is a hash of:
    #   timestamp
    #   type        -- one of :Sent, :Received, :System, :Deleted
    #   sender      -- when type is :Received
    #   message     -- can be nil
    #   attachment  -- can be nil
    #   inputFile   -- can be nil
    #

    def initialize(messages = nil, inputFile = nil, senderMap = nil)
      @messages = Hash.new
      @senders = Set.new
      @allYears = Set.new   # Set of years
      @allMonths = Hash.new # Hash of year => Set of year-month
      @allDays = Hash.new   # Hash of year-month => Set of year-month-day
      @count = 1
      setSenderMap(senderMap)
      add(messages, inputFile)
    end

    def setSenderMap(senderMap)
      @senderMap = senderMap ? senderMap : Hash.new
    end

    def getYears(from = nil, to = nil)
      years = Array.new
      @allYears.each { |year|
        yd = Date.strptime(year, "%Y")
        next if from and yd < from
        next if to and yd > to
        years << year
      }
      return years.sort
    end

    def getMonths(year = nil, from = nil, to = nil)
      if year
        years = [ year ]
      else
        years = getYears(from, to)
      end
      months = Array.new
      years.each { |year|
        if @allMonths.include?(year)
          @allMonths[year].each { |month|
            md = Date.strptime(month, "%Y-%m")
            next if from and md < from
            next if to and md > to
            months << month
          }
        end
      }
      return months.sort
    end

    def getDays(month = nil, from = nil, to = nil)
      if month
        months = [ month ]
      else
        months = getMonths(nil, from, to)
      end
      days = Array.new
      months.each { |month|
        if @allDays.include?(month)
          @allDays[month].each { |day|
            dd = Date.strptime(day, "%Y-%m-%d")
            next if from and dd < from
            next if to and dd > to
            days << day
          }
        end
      }
      return days.sort
    end

    def getTimes(day)
      return @messages.include?(day) ? @messages[day].keys.sort : Array.new
    end

    def getMessages(day = nil, time = nil)
      allMessages = Array.new

      if day
        days = [ day ]
      else
        days = getDays()
      end

      days.each { |day|
        if time
          times = [ time ]
        else
          times = getTimes(day)
        end

        times.each { |time|
          if @messages.include?(day) and @messages[day].include?(time)
            allMessages.concat(@messages[day][time])
          end
        }
      }

      return allMessages
    end

    def getMessagesFromTo(from = nil, to = nil)
      allMessages = Array.new
      days = getDays(nil, from, to)

      days.each { |day|
        dailyMessages = getMessages(day)
        allMessages.concat(dailyMessages)
      }

      return allMessages
    end

    def mapSender(sender)
      if !sender
        sender = ""
      end
      if @senderMap.include?(sender)
        return @senderMap[sender]
      end
      found = sender
      @senderMap.each { |key, value|
        if sender.include?(key)
          found = value
          break
        end
      }
      @senderMap[sender] = found
      return found
    end

    def getSenders()
      return @senders.to_a.sort
    end

    def getCount()
      return @count
    end

    def add(messages=nil, inputFile=nil)
      if messages
        messages.each { |message| addMessage(message, inputFile) }
      end
    end

    def addMessage(message, inputFile=nil)
      timestamp = message[:timestamp]
      year=timestamp.strftime("%Y")
      month=timestamp.strftime("%Y-%m")
      day=timestamp.strftime("%Y-%m-%d")
      sec=timestamp.strftime("%H:%M:%S")

      #
      # Update indexes
      #

      @allYears.add(year)

      if !@allMonths.include?(year)
        @allMonths[year] = Set.new
      end

      @allMonths[year].add(month)

      if !@allDays.include?(month)
        @allDays[month] = Set.new
      end

      @allDays[month].add(day)

      #
      # Map and index senders.
      #

      if message[:type] == :Received
        message[:sender] = mapSender(message[:sender])
        @senders.add(message[:sender]) if message[:sender]
      end

      #
      # Record message
      #

      if !@messages.include?(day)
        @messages[day] = Hash.new
      end

      if !@messages[day].include?(sec)
        @messages[day][sec] = Array.new
      end

      #
      # Avoid duplicates. Duplicates typically happen when overlapping
      # chat histories are imported.
      #

      if !contains(@messages[day][sec], message)
        if !message.include?(:inputFile) or !message[:inputFile]
          message[:inputFile] = inputFile
        end
        @messages[day][sec] << message
        @count = @count + 1
      end
    end

    def contains(arrayOfMessages, message)
      arrayOfMessages.each { |msg|
        if msg[:text] == message[:text] and msg[:attachment] == message[:attachment]
          return true
        end
      }
      return false
    end
  end
end
