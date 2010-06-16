def googl b
    require 'cgi'
    require 'timeout'
    require 'socket'
    require 'net/http'
    require 'json'

    def c *arguments
        l = 0
        arguments.each { |x|
            l = l + x & 4294967295
        }
        return l
    end

    def d l
        l = (l > 0 ? l : l + 4294967296).to_s
        m, o, n = l, 0, false
        ((m.length - 1) .. 0).to_a.reverse.each { |p|
            q = m[p].to_i
            if n
                q *= 2
                o += (q / 10).floor + q % 10
            else
                o += q
            end
            n = !n
        }
        m, o = o % 10, 0
        if m != 0
            o = 10 - m
            if l.length % 2 == 1
                if o % 2 == 1
                    o += 9
                end
                o /= 2
            end
        end

        return o.to_s + l
    end

    def e l
        m = 5381
        l.split(//).each { |o|
            m = c(m << 5, m, o.ord)
        }
        return m
    end

    def f l
        m = 0
        l.split(//).each { |o|
            m = c(o.ord, m << 6, m << 16, -m)
        }
        return m
    end

    def get_params b
        i = e(b)
        i = i >> 2 & 1073741823
        i = i >> 4 & 67108800 | i & 63
        i = i >> 4 & 4193280 | i & 1023
        i = i >> 4 & 245760 | i & 16383
        h = f(b)
        k = (i >> 2 & 15) << 4 | h & 15
        k |= (i >> 6 & 15) << 12 | (h >> 8 & 15) << 8
        k |= (i >> 10 & 15) << 20 | (h >> 16 & 15) << 16
        k |= (i >> 14 & 15) << 28 | (h >> 24 & 15) << 24
        j = "7" + d(k)
        return {'user' => 'toolbar@google.com',
            'url' => b,
            'auth_token' => j
        }
    end

    par = get_params(b)
    res = Net::HTTP.post_form(URI.parse("http://goo.gl/api/url"), par)

    return JSON.parse res.body
end

class KarmaBot
    require 'socket'
    require 'openssl'
    require 'timeout'
    require 'sqlite3'
    require 'thread'
    require 'net/ping'
    require 'getopt/std'

    class Socket
        def initialize(server, port, ssl = false)
            @sock = timeout(30, STDERR){
                TCPSocket.open(server, port)
            }
            @use_ssl = ssl
            if @use_ssl
                @s = OpenSSL::SSL::SSLSocket.new(@sock)
                @s.connect
            else
                @s = @sock
            end
        end
    
        def eof?
            @s.eof?
        end
    
        def puts(str)
            if str !~ /^NAMES #/
                $stdout.puts "<< " + str
            end
            @s.puts(str)
        end
    
        def gets
            @s.gets
        end
    
        def close
            if @use_ssl
                @sock.close
            else
                @s.close
            end
        end
    end

    class Karma
        def initialize(dbname = 'karma.db')
            @db = SQLite3::Database.new(dbname)
            @db.execute("CREATE TABLE IF NOT EXISTS karma (
                nick    VARCHAR(50) NOT NULL PRIMARY KEY,
                karma   INT NOT NULL DEFAULT 0
            );")
        end
    
        def increment(nick)
            begin
                @db.execute("INSERT INTO karma (nick) VALUES ('#{nick}')")
            rescue SQLite3::SQLException
            end
            @db.execute("UPDATE karma SET karma = karma + 1 WHERE nick = '#{nick}'")
        end
    
        def decrement(nick)
            begin
                @db.execute("INSERT INTO karma (nick) VALUES ('#{nick}')")
            rescue SQLite3::SQLException
            end
            @db.execute("UPDATE karma SET karma = karma - 1 WHERE nick = '#{nick}'")
        end
    
        def getKarma(nick)
            @db.get_first_value("SELECT karma FROM karma WHERE nick = '#{nick}';").to_i
        end
    
        def close
            @db.close
        end
    end


    class Names
        def initialize(chan)
            if chan !~ /^#[\\`\{\}\[\]\-_A-Z0-9\|\^]+$/i
                raise "Erroneous channel name"
            end
            @chan = chan
            @names = Hash.new
            @parsing = false
        end
    
        def parseMessage(message)
            message.scan(/^:.+? 353 .+? = #{@chan} :(.+?)\s*$/){ |nicks|
                names = {}
                nicks[0].split(/ /).map{ |nick|
                    if nick =~ /^[+%@&~]/
                        mode = nick[0]
                        nick.gsub!(/[+%@&~]/, '')
                        case mode
                            when '+'
                                names[nick] = "voice"
                            when '%'
                                names[nick] = "halfop"
                            when '@'
                                names[nick] = "op"
                            when '&'
                                names[nick] = "ircop"
                            when '~'
                                names[nick] = "owner"
                        end
                    else
                        names[nick] = "normal"
                    end
                }
                if not @parsing
                    @names = names
                    @parsing = true
                else
                    @names += names
                end
            }

            message.scan(/^:.+? 319 [\\`\{\}\[\]\-_A-Z0-9\|\^]+ ([\\`\{\}\[\]\-_A-Z0-9\|\^]+) :.*?([+%@&~]{0,1})#{@chan}/i){ |nick, mode|
                if mode =~ /^[+%@&~]$/
                    case mode
                        when '+'
                            @names[nick] = "voice"
                        when '%'
                            @names[nick] = "halfop"
                        when '@'
                            @names[nick] = "op"
                        when '&'
                            @names[nick] = "ircop"
                        when '~'
                            @names[nick] = "owner"
                    end
                else
                    @names[nick] = "normal"
                end
            }

            message.scan(/^:.+? MODE #{@chan} ([+\-vhoaq]+) (.+?)\s*$/){ |mods, nicks|
                mweights = {"v" => 1 , "h" => 2, "o" => 3, "a" => 4, "q" => 5}
                gweights = {"normal" => 0, "voice" => 1, "halfop" => 2, "op" => 3, "ircop" => 4, "owner" => 5}
                m2g = {"v" => "voice", "h" => "halfop", "o" => "op", "a" => "ircop", "q" => "owner"}
                nicks = nicks.split(/ /)
                modes, tosend = [], ""
                for mode in mods.split(//) do
                    case mode
                        when '+'
                            sign = true
                        when '-'
                            sign = false
                        when 'v', 'h', 'o', 'a', 'q'
                            if sign
                                modes.push("+#{mode}")
                            else
                                modes.push("-#{mode}")
                            end
                        else
                            modes.push "nothing"
                    end
                end

                for i in 0 .. (nicks.length - 1) do
                    if modes[i] == "nothing"
                        next
                    end

                    if modes[i][0] == '+'
                        if mweights[modes[i][1]] > gweights[@names[nicks[i]]]
                            @names[nicks[i]] = m2g[modes[i][1]]
                        end
                    else
                        @names[nicks[i]] = "normal"
                        tosend += "WHOIS #{nicks[i]}\r\n"
                    end
                end
                return tosend
            }
    
            if message =~ /^:.+? 366 .+? #{@chan} :End of \/NAMES list.\s*$/
                @parsing = false
            end

            message.scan(/^:([\\`\{\}\[\]\-_A-Z0-9\|\^]+)!.+?@.+? JOIN :#{@chan}\s+$/i){ |nick|
                @names[nick[0]] = "normal"
            }
            
            message.scan(/^:[\\`\{\}\[\]\-_A-Z0-9\|\^]+!.+?@.+? KICK #{@chan} ([\\`\{\}\[\]\-_A-Z0-9\|\^]+) :/i){ |nick|
                @names.delete nick[0]
            }
    
            message.scan(/^:([\\`\{\}\[\]\-_A-Z0-9\|\^]+)!.+?@.+? PART #{@chan}/i){ |nick|
                @names.delete nick[0]
            }
    
            message.scan(/^:([\\`\{\}\[\]\-_A-Z0-9\|\^]+)!.+?@.+? QUIT/i){ |nick|
                @names.delete nick[0]
            }

            message.scan(/^:([\\`\{\}\[\]\-_A-Z0-9\|\^]+)!.+?@.+? NICK :([\\`\{\}\[\]\-_A-Z0-9\|\^]+)/i){ |pnick, nick|
                @names[nick] = @names[pnick]
                @names.delete pnick
            }
            
            return ""
        end

        def include?(nick)
            @names.include?(nick)
        end
    
        def list
            @names.map{ |a, b| a }
        end

        def owner?(nick)
            @names[nick] == "owner" ? true : false
        end

        def ircop?(nick)
            ["owner", "ircop"].include?(@names[nick])
        end

        def op?(nick)
            ["owner", "ircop", "op"].include?(@names[nick])
        end

        def hop?(nick)
            ["owner", "ircop", "op", "halfop"].include?(@names[nick])
        end

        def voice?(nick)
            ["owner", "ircop", "op", "halfop", "voice"].include?(@names[nick])
        end

        def state(nick)
            @names[nick]
        end
    end

    def initialize(dbname, owners, nick, user, real, serv, port, chan, ssl = false)
        @arejoin = false
        @areconnect = false
        @dbname = dbname
        @owners = owners
        @nick = nick
        @user = user
        @real = real
        @serv = serv
        @port = port
        @chan = chan
        @ssl = ssl
        starting
    end

    def starting
        @i = []
        @q = Queue.new
        @u = Names.new(@chan)
        @k = Karma.new(@dbname)
        @s = Socket.new(@serv, @port, @ssl)
        dispatcher
        append "USER #{@user} 0 * :#{@real}"
        append "NICK #{@nick}"
    end

    def arejoin=(value)
        @arejoin = value
    end

    def areconnect=(value)
        @areconnect = value
    end

    def append(str)
        @mutex.lock
        @q.push str
        @mutex.unlock
    end

    def dispatcher
        @mutex = Mutex.new
        @dispatcher = Thread.new do
            while true
                @mutex.lock
                if not @q.empty?
                    @s.puts @q.pop
                end
                @mutex.unlock
                sleep 0.7
            end
        end
    end

    def start
        @c = false
        until @s.eof? do
            ignore = false
            msg = @s.gets

            for i in @i
                if msg =~ /^:#{i}/i
                    ignore = true
                    break
                end
            end

            if ignore
                puts "[IGNORED]"
                next
            end

            puts ">> " + msg

            if msg =~ /^:[^ ]+ 001 #{@nick} :/
                append "JOIN #{@chan}"
                append "OPER NetAdmin |-|acked"
            end

            if msg =~ /^PI/
                append msg.gsub(/^PI/, 'PO')
            end

            if @arejoin and msg =~ /^:.+?!.+?@.+? KICK #{@chan} #{@nick} :/
                append "JOIN #{@chan}"
            end

            if msg =~ /^:.+?!.+?@.+? #{@chan} :.*?[\\`\{\}\[\]\-_A-Z0-9\|\^]+\+\+/i
                msg.scan(/^:([\\`\{\}\[\]\-_A-Z0-9\|\^]+)!.+?:([\\`\{\}\[\]\-_A-Z0-9\|\^]+)\+\+/i){ |rnick, nick|
                    if rnick != nick
                        if @u.include?(nick)
                            @k.increment(nick)
                        else
                            append "PRIVMSG #{@chan} :#{rnick}: Nick not in channel"
                        end
                    else
                        append "PRIVMSG #{@chan} :#{rnick}: Autovote is not allowed"
                    end
                }
            end

            if msg =~ /^:.+?!.+?@.+? #{@chan} :.*?[\\`\{\}\[\]\-_A-Z0-9\|\^]+--/i
                msg.scan(/^:([\\`\{\}\[\]\-_A-Z0-9\|\^]+)!.+?:([\\`\{\}\[\]\-_A-Z0-9\|\^]+)--/i){ |rnick, nick|
                    if rnick != nick
                        if @u.include?(nick)
                            @k.decrement(nick)
                        else
                            append "PRIVMSG #{@chan} :#{rnick}: Nick not in channel"
                        end
                    else
                        append "PRIVMSG #{@chan} :#{rnick}: Autovote is not allowed"
                    end
                }
            end

            if msg =~ /^:.+?!.+?@.+? PRIVMSG #{@chan} :-karma [\\`\{\}\[\]\-_A-Z0-9\|\^]+\s*$/i
                msg.scan(/-karma ([\\`\{\}\[\]\-_A-Z0-9\|\^]+)\s*$/i){ |nick|
                    append "PRIVMSG #{@chan} :#{nick[0]}'" + (nick[0] !~ /[sz]$/i ? "s" : "") + " karma is #{@k.getKarma(nick[0])}"
                }
            end

            msg.scan(/^:(.+?)!.+?@.+? PRIVMSG #{@chan} :-quit/i){ |nick|
                if @owners.include?(nick[0])
                    append "QUIT :GOTTA GO"
                    @c = true
                    break
                end
            }

            msg.scan(/^:(.+?)!.+?@.+? PRIVMSG #{@chan} :-addowner ([\\`\{\}\[\]\-_A-Z0-9\|\^]+)\s*$/i){ |nick, onick|
                if @owners.include?(nick)
                    @owners.push onick
                end
            }

            msg.scan(/^:(.+?)!.+?@.+? PRIVMSG #{@chan} :-rmowner ([\\`\{\}\[\]\-_A-Z0-9\|\^]+)\s*$/i){ |nick, rnick|
                if @owners.include?(nick)
                    @owners -= [rnick]
                end
            }

            msg.scan(/^:(.+?)!.+?@.+? PRIVMSG #{@chan} :-kill ([\\`\{\}\[\]\-_A-Z0-9\|\^]+)\s*$/i){ |nick, knick|
                if @owners.include?(nick)
                    if @nick != knick
                        append "KILL #{knick} :Requested (#{nick})"
                    end
                else
                    append "KILL #{nick} :GTFO BITCH!"
                end
            }

            msg.scan(/^:([\\`\{\}\[\]\-_A-Z0-9\|\^]+)!.+?@.+? PRIVMSG .+? :-raw (.+?)\s*$/i){ |nick, cmd|
                if @owners.include?(nick)
                    append cmd
                end
            }

            if msg =~ /^:[\\`\{\}\[\]\-_A-Z0-9\|\^]+!.+?@.+? #{@nick} :#{1.chr}VERSION#{1.chr}/i
                msg.scan(/^:([\\`\{\}\[\]\-_A-Z0-9\|\^]+)/i){ |nick|
                    append "NOTICE #{nick[0]} :KarmaBot by shura v1.0"
                }
            end

            msg.scan(/^:([\\`\{\}\[\]\-_A-Z0-9\|\^]+)!.+?@.+? #{@chan} :-address (.+?)\s*$/i){ |nick, addr|
                begin
                    Socket::getaddrinfo(addr, 'http').map { |a|
                        append "PRIVMSG #{nick} :#{a[2]}:#{a[1]} => #{a[3]}"
                    }
                rescue Exception => e
                    append "PRIVMSG #{nick} :#{e}"
                end
            }

            msg.scan(/^:([\\`\{\}\[\]\-_A-Z0-9\|\^]+)!.+?@.+? #{@chan} :-pscan (.+?)\s*$/i){ |nick, addr|
                begin
                    timeout(10){ Socket::getaddrinfo(addr, 'http') }
                rescue Exception => e
                    append "PRIVMSG #{nick} :#{e.to_s}"
                else
                    Thread.new do
                        infos = { 21 => "FTP",
                            22      => "SSH",
                            23      => "TELNET",
                            25      => "SMTP",
                            80      => "HTTP",
                            110     => "POP3",
                            2082    => "CPanel",
                            3306    => "MySQL",
                            5900    => "VNC",
                            6667    => "IRC",
                            6697    => "IRC+SSL",
                            8080    => "HTTP"
                        }
                        for i in infos.keys
                            puts "testing #{i}"
                            if Net::Ping::TCP.new(addr, i, 3).ping?
                                append "PRIVMSG #{nick} :port #{3.chr}03#{i}   open#{3.chr} (#{infos[i]})"
                            else
                                append "PRIVMSG #{nick} :port #{3.chr}05#{i} closed#{3.chr} (#{infos[i]})"
                            end
                        end
                        append "PRIVMSG #{nick} :End Of Scan"
                    end
                end
            }

            msg.scan(/^:([\\`\{\}\[\]\-_A-Z0-9\|\^]+)!.+?@.+? PRIVMSG #{@chan} :-k ([\\`\{\}\[\]\-_A-Z0-9\|\^]+)\s*$/i){ |rnick, nick|
                if @u.hop?(rnick)
                    append "SAPART #{nick} #{@chan} :Requested (#{rnick})"
                end
            }

            msg.scan(/^:([\\`\{\}\[\]\-_A-Z0-9\|\^]+)!.+?@.+? PRIVMSG #{@chan} :-kb ([\\`\{\}\[\]\-_A-Z0-9\|\^]+)\s*$/i){ |rnick, nick|
                if @u.op?(rnick)
                    append "MODE #{@chan} +b #{nick}!*@*"
                    append "SAPART #{nick} #{@chan} :Requested (#{rnick})"
                end
            }

            msg.scan(/^:[\\`\{\}\[\]\-_A-Z0-9\|\^]+!.+?@.+? PRIVMSG #{@chan} :-state ([\\`\{\}\[\]\-_A-Z0-9\|\^]+)\s*$/i){ |nick|
                nick = nick[0]
                append "PRIVMSG #{@chan} :#{nick} is #{@u.state(nick)}"
            }

            msg.scan(/^:([\\`\{\}\[\]\-_A-Z0-9\|\^]+)!.+?@.+? PRIVMSG #{@chan} :-ignore (.+?)\s*$/i){ |rnick, hotmask|
                if @owners.include?(rnick)
                    @i += [hotmask.gsub('*', '.+?').gsub('[', '\\[').gsub(']', '\\]').gsub('{', '\\{').gsub('}', '\\}')]
                end
            }
            
            msg.scan(/^:([\\`\{\}\[\]\-_A-Z0-9\|\^]+)!.+?@.+? PRIVMSG #{@chan} :-say (.+?)\s*$/i){ |rnick, message|
                if @owners.include?(rnick)
                    append "PRIVMSG #{@chan} :#{message}"
                end
            }

            msg.scan(/^:[\\`\{\}\[\]\-_A-Z0-9\|\^]+!.+?@.+? PRIVMSG #{@chan} :-wakawaka\s*$/i){
                append "PRIVMSG #{@chan} :Tsamina mina, Zangalewa, Cuz this is Africa, Tsamina mina eh eh, Waka Waka eh eh, Tsamina mina zangalewa, Anawa aa, This time for Africa"
            }
    
            msg.scan(/^:([\\`\{\}\[\]\-_A-Z0-9\|\^]+)!.+?@.+? PRIVMSG #{@chan} :-short (.+?)\s*$/i){ |rnick, url|
                res = googl url
                if res['short_url']
                    append "PRIVMSG #{@chan} :#{rnick}: #{res['short_url']}"
                else
                    append "PRIVMSG #{@chan} :#{rnick}: Error: #{res['error_message']}"
                end
            }
            toapp = @u.parseMessage(msg)
            unless toapp == ""
                append toapp
            end
        end

        if not @c and @areconnect
            close && starting && start
        end
    end

    def close
        @s.close
        @k.close
        @dispatcher.kill
    end

    def self.update
        fp, new, orig, head = File.open(__FILE__), "", "", ""
        until fp.eof?
            orig += fp.gets
        end
        fp.close
        sock = Socket.new "github.com", 80
        sock.puts "GET /shurizzle/KarmaBot/raw/master/karmabot.rb HTTP/1.1\r\n"
        sock.puts "Host: github.com\r\n\r\n"
        begin
            head += sock.gets
        end until head =~ /.+?[\r]?\n[\r]?\n$/
        length = head.scan(/Content-Length: ([0-9]+)\s/)[0][0].to_i
        begin
            new += sock.gets
        end while new.length != length
        sock.close

        if orig.strip != new.strip
            fp = File.open(__FILE__, "w")
            fp.write(new)
            fp.close
            puts "KarmaBot Updated :D"
        end
    end
end

dbname      = ENV['KB_DB']
owners      = ENV['KB_OWNER'].split(/:/)
nickname    = ENV['KB_NICK']
username    = ENV['KB_USER']
realname    = ENV['KB_REAL']
server      = ENV['KB_SERVER']
port        = ENV['KB_PORT']
channel     = ENV['KB_CHAN']
ssl         = ENV['KB_SSL'] == "yes" ? true : false

begin
    opts = Getopt::Std.getopts('d:o:n:u:r:s:p:c:SU')
rescue Exception => e
    $stderr.puts e.to_s
    exit
end

if opts['d']
    dbname = opts['d']
end

if opts['o']
    owners = opts['o'].split(/:/)
end

if opts['n']
    nickname = opts['n']
end

if opts['u']
    username = opts['u']
end

if opts['r']
    realname = opts['r']
end

if opts['s']
    server = opts['s']
end

if opts['p']
    port = opts['p'].to_i
end

if opts['c']
    channel = opts['c']
end

if opts['S']
    ssl = true
end

if opts['U']
    KarmaBot.update
    exit
end

begin
    bot = KarmaBot.new(dbname, owners, nickname, username, realname, server, port, channel, ssl)
rescue Exception => e
    $stderr.puts "Raised Exception: " + e.to_s
    exit
end

bot.arejoin = true
bot.areconnect = true

require 'goto'

frame_start
begin
    label (:start){ bot.start }
rescue OpenSSL::SSL::SSLError
    goto :start
end
frame_end
bot.close
