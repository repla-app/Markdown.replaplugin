require 'webrick'
require 'kramdown'

require 'securerandom'
STYLSHEET_TOKEN = SecureRandom.uuid
RASTER_TOKEN = SecureRandom.uuid

module WEBrick
  # Servlet
  module HTTPServlet
    # MarkdownHandler
    class MarkdownHandler < AbstractServlet
      def initialize(server, local_path)
        super(server, local_path)
        @local_path = local_path
      end

      # rubocop:disable Naming/MethodName
      def do_GET(_req, res)
        title = File.basename(@local_path)
        # rubocop:enable Naming/MethodName
        html = Kramdown::Document.new(IO.read(@local_path)).to_html
        res.body = <<~BODY
          <!DOCTYPE html>
          <html lang="en">
          <head>
            <title>#{title}</title>
            <meta charset="utf-8" />
            <link rel="stylesheet" href="/#{RASTER_TOKEN}">
            <link rel="stylesheet" href="/#{STYLSHEET_TOKEN}">
          <html>
          <body>
          #{html}
          </body>
          </html>
        BODY
        res['content-type'] = 'text/html'
      end
    end
    FileHandler.add_handler('md', MarkdownHandler)
    FileHandler.add_handler('markdown', MarkdownHandler)
  end
end

module Repla
  module Markdown
    # Server
    class Server
      def initialize(path, filename = nil, delegate = nil)
        @path = path
        @delegate = delegate
        @filename = filename
      end

      def start
        rd, wt = IO.pipe
        @server = WEBrick::HTTPServer.new(
          Port: 0,
          DocumentRoot: @path,
          StartCallback: proc do
                           # Write `1` to signal server start
                           wt.write(1)
                           wt.close
                         end
        )
        @port = @server.config[:Port]
        @server.mount_proc "/#{STYLSHEET_TOKEN}" do |_req, res|
          stylesheet_path = File.join(File.dirname(__FILE__),
                                      '..',
                                      'css/style.css')
          res.body = IO.read(stylesheet_path)
        end
        @server.mount_proc "/#{RASTER_TOKEN}" do |_req, res|
          stylesheet_path = File.join(
            File.dirname(__FILE__),
            '..',
            'bundle/ruby/2.4.0/gems/raster-0.2.3/dist/css/raster.css'
          )
          res.body = IO.read(stylesheet_path)
        end
        @pid = fork do
          rd.close
          @server.start
          %w[INT TERM QUIT].each do |signal|
            trap(signal) { @server.shutdown }
          end
        end
        wt.close
        # Read `1` to know to continue when server is started
        rd.read(1)
        rd.close

        url = url_for_subpath(@filename)
        @delegate.load_url(url) unless @delegate.nil?
      end

      def shutdown(signal)
        Process.kill(signal, -Process.getpgid(@pid))
      end

      def shutdown_light(signal)
        # This leaks processes when the app quits or crashes, but tests use it
        # because using the harder kill also kills the test process
        Process.kill(signal, @pid)
      end

      def url_for_subpath(subpath)
        "http://localhost:#{@port}/#{ERB::Util.url_encode(subpath)}"
      end
    end
  end
end
