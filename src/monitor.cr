require "http"
require "tallboy"
require "clim"
require "wafalyzer"
require "colorize"

module Monitor
  VERSION = "0.1.0"

  class Run < Clim
    PROBLOMATIC_STATUS_CODES = {
      401 => "Unauthorized - The request requires user authentication.",
      403 => "Forbidden - The server understood the request, but is refusing to fulfill it.",
      429 => "Too Many Requests - This means we are being rate limited",
      500 => "Internal Server Error - This means something is wrong with the server",
      502 => "Bad Gateway - This means something is wrong with the server",
      503 => "Service Unavailable - This means something is wrong with the server",
      504 => "Gateway Timeout - This means something is wrong with the server",
    }

    main do
      desc <<-DESC
        ██████╗ ██████╗ ██╗ ██████╗ ██╗  ██╗████████╗███████╗███████╗ ██████╗              ███╗   ███╗ ██████╗ ███╗   ██╗██╗████████╗ ██████╗ ██████╗
        ██╔══██╗██╔══██╗██║██╔════╝ ██║  ██║╚══██╔══╝██╔════╝██╔════╝██╔════╝              ████╗ ████║██╔═══██╗████╗  ██║██║╚══██╔══╝██╔═══██╗██╔══██╗
        ██████╔╝██████╔╝██║██║  ███╗███████║   ██║   ███████╗█████╗  ██║         █████╗    ██╔████╔██║██║   ██║██╔██╗ ██║██║   ██║   ██║   ██║██████╔╝
        ██╔══██╗██╔══██╗██║██║   ██║██╔══██║   ██║   ╚════██║██╔══╝  ██║         ╚════╝    ██║╚██╔╝██║██║   ██║██║╚██╗██║██║   ██║   ██║   ██║██╔══██╗
        ██████╔╝██║  ██║██║╚██████╔╝██║  ██║   ██║   ███████║███████╗╚██████╗              ██║ ╚═╝ ██║╚██████╔╝██║ ╚████║██║   ██║   ╚██████╔╝██║  ██║
        ╚═════╝ ╚═╝  ╚═╝╚═╝ ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚══════╝╚══════╝ ╚═════╝              ╚═╝     ╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚═╝   ╚═╝    ╚═════╝ ╚═╝  ╚═╝
        DESC
      usage "monitor --url <url>"
      version "Version 0.1.0"
      option "-u URL", "--url=URL", type: String, desc: "Target URL.", required: true
      option "-c CONCURRENCY", "--concurrency=CONCURRENCY", type: Int32, desc: "Number of concurrent requests to make.", default: 10
      option "-t TOTAL_REQUESTS", "--total-requests=TOTAL_REQUESTS", type: Int32, desc: "Total number of requests to make.", default: 1000
      run do |opts, args|
        uri = URI.parse(opts.url)
        unless uri.host && uri.scheme
          raise "Error: URL Is Malformed"
        end
        response_channel = Channel(Int32 | Exception).new
        uri_channel = Channel(URI).new
        opts.concurrency.times do
          spawn do
            request_handlers(uri_channel, response_channel)
          end
        end
        spawn do
          opts.total_requests.times do
            uri_channel.send(uri)
          end
        end

        responses = Hash(String | Int32, Int32).new(0)
        exception_messages = Hash(String, String).new
        wafs = Array(Wafalyzer::Waf).new
        begin
          wafs = Wafalyzer.detect(url: uri.to_s)
        rescue Exception
        end
        opts.total_requests.times do |i|
          response = response_channel.receive
          if response.is_a?(Exception)
            unless exception_messages[response]?
              exception_messages[response.class.to_s] = response.message.to_s
            end
            responses[response.class.to_s] += 1
          else
            responses[response] += 1
          end

          table = Tallboy.table do
            columns do
              add "Responses"
              add "Count"
              add "Description"
            end
            header
            responses.each do |code, count|
              case code
              when Int32
                row [code, count, PROBLOMATIC_STATUS_CODES[code]? || "OK"]
              when String
                row [code, count, exception_messages[code]]
              end
            end
          end
          system("clear")
          puts "WAFs detected: #{wafs.map(&.to_s).join(", ")}".colorize(:red).mode(:bold) unless wafs.empty?
          puts table
        end
      end

      def request_handlers(uri_channel : Channel(URI), response_channel : Channel(Int32 | Exception))
        loop do
          uri = uri_channel.receive
          client = HTTP::Client.new(uri)
          client.read_timeout = 30.seconds
          client.connect_timeout = 30.seconds
          response = client.get(uri.path || "/")

          response_channel.send(response.status_code)
        rescue e : Exception
          response_channel.send(e)
        ensure
          client.close if client
        end
      end
    end
  end
end

Monitor::Run.start(ARGV)
