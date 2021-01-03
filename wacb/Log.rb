module WhatsAppChatBeautifier
  class LogOutput
    def begin(info)
    end

    def end()
    end
  end

  class ConsoleOutput < LogOutput
    def initialize(verbose=0)
      @verbose = verbose
    end
    def begin(info)
      if @verbose > 0
        print(info)
        print(" ... ")
        $stdout.flush
      end
    end

    def end()
      if @verbose > 0
        puts("done.")
      end
    end
  end
end
