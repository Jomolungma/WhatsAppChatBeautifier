module WhatsAppChatBeautifier
  #
  # ----------------------------------------------------------------------
  # Parser for Excel files exported from Elcomsoft Explorer for WhatsApp
  # ----------------------------------------------------------------------
  #

  class ExwaParser
    @@nonMessageTopRows = 2

    def initialize()
      require 'rubyXL'
      @messages = Array.new
      @sheet = nil
      @selected = nil
      @from = nil
      @to = nil
    end

    def getMe()
      return nil
    end

    def getMessages()
      raise "Must select a chat." if !@selected
      return @messages
    end

    def load(xlsxData, from=nil, to=nil)
      book = RubyXL::Parser::parse_buffer(xlsxData)
      @sheet = book['Messages']
      @from = from
      @to = to
      raise "Oops, worksheet \"Messages\" not found." if !@sheet
      raise "Oops, expected the text \"Messages\" in cell B1" if @sheet[0][1].value != "Messages"
    end

    def matchChatName(subChatName)
      chatNames = getChatNames
      chatNames.keys.each { |chatName|
        return chatName if chatName.include?(subChatName)
      }
      return nil
    end

    def select(selectedChatName)
      @selected = true
      @sheet.sheet_data.rows.each { |row|
        rowIndex = row.index_in_collection - @@nonMessageTopRows
        next if rowIndex < 0
        next if !row[1]
        chatName = getChatNameFromRow(row)
        if chatName.include?(selectedChatName)
          message = parseMessage(rowIndex)
          next if @from and message[:timestamp].to_date < @from
          next if @to and message[:timestamp].to_date > @to
          if message[:message] or message[:attachment]
            @messages << message
          end
        end
      }
    end

    def count()
      return sheet.sheet_data.rows.size - @@nonMessageTopRows
    end

    def parseMessage(messageIndex)
      rowIndex = messageIndex + @@nonMessageTopRows
      row = @sheet[rowIndex]
      timestamp = row[8].value

      if row[7]
        if row[7].formula
          formula = row[7].formula.expression
          raise "Oops" if formula[0,9] != "HYPERLINK"
          message = formula.match('"([^"]*)"')[1]
        else
          message = row[7].value
        end
      else
        message = nil
      end

      if row[12] and row[12].formula
        formula = row[12].formula.expression
        raise "Oops" if formula[0,9] != "HYPERLINK"
        attachment = formula.match('"([^"]*)"')[1].gsub('\\', '/')
      else
        attachment = nil
      end

      sender = nil
      messageType = row[10].value

      if messageType.include?("Whats App")
        type = row[5].value == "Incoming" ? :Received : :Sent
        sender = type == :Received ? row[3].value : nil
        message = row[14].value if messageType.include?("Location")
      elsif messageType == "System"
        type = :System
      elsif messageType == "Deleted"
        type = :Deleted
      end

      return {
        :timestamp => timestamp,
        :type => type,
        :sender => sender,
        :message => message,
        :attachment => attachment
      }
    end

    def getChatNames()
      chatNames = Hash.new

      @sheet.sheet_data.rows.each do |row|
        next if row.index_in_collection < 2
        next if row[7] == nil and row[12] == nil

        chatName = getChatNameFromRow(row)
        if not chatNames.has_key?(chatName)
          chatNames[chatName] = Set.new
        end
        sender = row[3]
        receiver = row[4]
        if sender != nil
          sender = sender.value
          chatNames[chatName].add(sender) unless sender.index(chatName) == 0
        end
      end

      return chatNames
    end

    def getChatNameFromRow(row)
      chatName = row[1].value
      p = chatName.index('(')
      if p != nil
        chatName = chatName[0,p]
      end
      return chatName.strip
    end
  end
end
