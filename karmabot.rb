require 'socket'
require 'openssl'
require 'timeout'
require 'sqlite3'
require 'thread'
require 'net/ping'
require 'getopt/std'

dbname      = ENV['KB_DB']
owner       = ENV['KB_OWNER']
nickname    = ENV['KB_NICK']
username    = ENV['KB_USER']
realname    = ENV['KB_REAL']
server      = ENV['KB_SERVER']
port        = ENV['KB_PORT']
channel     = ENV['KB_CHAN']
ssl         = ENV['KB_SSL'] == "yes" ? true : false

opts = Getopt::Std.getopts('d:o:n:u:r:s:p:c:S')

if opts['d']
    dbname = opts['d']
end

if opts['o']
    owner = opts['o']
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

class Socket
    def initialize(server, port, ssl = false)
        @sock = timeout(30, STDERR){
            TCPSocket.open(server, port)
        }
        @use_ssl = ssl
        if @use_ssl
            ssl = OpenSSL::SSL::SSLSocket.new(@sock)
            ssl.connect
            @s = ssl
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
        @names = []
        @parsing = false
    end

    def parseMessage(message)
        message.scan(/^:.+? 353 .+? = #{@chan} :(.+?)\s*$/){ |nicks|
            if not @parsing
                @names = nicks[0].gsub(/[+%@&~]/, '').split(/ /)
                @parsing = true
            else
                @names += nicks[0].gsub(/[+%@&~]/, '').split(/ /)
            end
        }

        if message =~ /^:.+? 366 .+? #{@chan} :End of \/NAMES list.\s*$/
            @parsing = false
        end

        message.scan(/^:([\\`\{\}\[\]\-_A-Z0-9\|\^]+)!.+?@.+? JOIN :#{@chan}\s+$/i){ |nick|
            @names += nick
        }
        
        message.scan(/^:[\\`\{\}\[\]\-_A-Z0-9\|\^]+!.+?@.+? KICK #{@chan} ([\\`\{\}\[\]\-_A-Z0-9\|\^]+) :/i){ |nick|
            @names -= nick
        }

        message.scan(/^:([\\`\{\}\[\]\-_A-Z0-9\|\^]+)!.+?@.+? PART #{@chan}/i){ |nick|
            @names -= nick
        }

        message.scan(/^:([\\`\{\}\[\]\-_A-Z0-9\|\^]+)!.+?@.+? QUIT/i){ |nick|
            @names -= nick
        }

        message.scan(/^:([\\`\{\}\[\]\-_A-Z0-9\|\^]+)!.+?@.+? NICK :([\\`\{\}\[\]\-_A-Z0-9\|\^]+)/i){ |pnick, nick|
            @names -= [pnick]
            @names += [nick]
        }
    end

    def include?(nick)
        @names.include?(nick)
    end

    def list
        @names
    end
end

class KarmaBot
    def initialize(dbname, owner, nick, user, real, serv, port, chan, ssl = false)
        @arejoin = false
        @chan = chan
        @nick = nick
        @owner = owner
        @q = Queue.new
        @u = Names.new(chan)
        @k = Karma.new(dbname)
        @s = Socket.new(serv, port, ssl)
        dispatcher
        append "USER #{user} 0 * :#{real}"
        append "NICK #{nick}"
    end

    def arejoin=(value)
        @arejoin = value
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
        @g = false
        until @s.eof? do
            msg = @s.gets

            puts ">> " + msg

            if msg =~ /^:.+?001.+?#{@nick} :/
                append "JOIN #{@chan}"
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

            if msg =~ /^:.+?!.+?@.+? #{@chan} :-karma [\\`\{\}\[\]\-_A-Z0-9\|\^]+\s*$/i
                msg.scan(/-karma ([\\`\{\}\[\]\-_A-Z0-9\|\^]+)\s*$/i){ |nick|
                    append "PRIVMSG #{@chan} :#{nick[0]}'s karma is #{@k.getKarma(nick[0])}"
                }
            end

            if msg =~ /^:#{@owner}!.+?@.+? #{@chan} :-quit\s*$/
                append "QUIT :GOTTA GO"
                break
            end

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

            @u.parseMessage(msg)
        end
    end

    def end
        @s.close
        @k.close
        @dispatcher.kill
    end
end


begin
    bot = KarmaBot.new(dbname, owner, nickname, username, realname, server, port, channel, ssl)
rescue Exception => e
    $stderr.puts e.to_s
    exit
end

bot.arejoin = true

bot.start
bot.end
