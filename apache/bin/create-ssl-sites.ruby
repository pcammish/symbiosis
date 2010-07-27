#!/usr/bin/ruby
#
# NAME
#
#   create-ssl-sites -- Auto-configure SSL sites
#
# SYNOPSIS
#
#  Help Options:
#
#   --help        Show the help information for this script.
#   --verbose     Show debugging information.
#
# DETAILS
#
#   This script is designed to iterate over the domains hosted
#  upon a Symbiosis system, and configure Apache to listen appropriate
#  when a domain is configured for SSL hosting and not yet configured.
#
# AUTHOR
#
#   Steve Kemp <steve@bytemark.co.uk>
#


require 'erb'
require 'getoptlong'

require 'symbiosis/domains.rb'



#
# A helper class which copes with SSL-domains.
#
#
class SSLConfiguration

  #
  # The domain this object is working with.
  #
  attr_reader :domain



  #
  # Constructor.
  #
  def initialize( domain )
    @domain = domain
  end



  #
  # Is SSL enabled for the domain?
  #
  # SSL is enabled if we have:
  #
  #  /srv/$domain/config/ip
  #
  # And one of:
  #
  #  /srv/$domain/config/ssl.key
  #  /srv/$doamin/config/ssl.combined
  #
  def ssl_enabled?

    #
    #  SSL is never enabled unless we have /config/ip
    #
    if ( ! File.exists?( "/srv/#{@domain}/config/ip" ) )
      return false
    end

    if ( File.exists?( "/srv/#{@domain}/config/ssl.key" ) ||
         File.exists?( "/srv/#{@domain}/config/ssl.combined" ) )
      true
    else
      false
    end
  end



  #
  # Is there an Apache site enabled for this domain?
  #
  def site_enabled?
    File.exists?( "/etc/apache2/sites-enabled/#{@domain}.ssl" )
  end



  #
  # Do we redirect to the SSL only version of this site?
  #
  def mandatory_ssl?
    if ( File.exists?( "/srv/#{@domain}/config/ssl-only" ) )
      true
    else
      false
    end
  end



  #
  # Remove the apache file.
  #
  def remove_site

    if ( File.exists?( "/etc/apache2/sites-enabled/#{@domain}.ssl" ) )
      File.unlink( "/etc/apache2/sites-enabled/#{@domain}.ssl" )
    end

    if ( File.exists?( "/etc/apache2/sites-available/#{@domain}.ssl" ) )
      File.unlink( "/etc/apache2/sites-available/#{@domain}.ssl" )
    end
  end



  #
  # Get the IP for this domain.
  #
  def ip
    File.open("/srv/#{@domain}/config/ip"){|fh| fh.readlines}.first.chomp
  end



  #
  # Return the bundle configuration to use, if any.
  #
  def bundle
    if ( File.exists?( "/srv/#{@domain}/config/ssl.bundle" ) )
      "SSLCertificateChainFile /srv/#{@domain}/config/ssl.bundle"
    else
      ""
    end
  end



  #
  # Return the certificate file
  #
  def certificate

    if ( File.exists?( "/srv/#{@domain}/config/ssl.combined" ) )
      return "SSLCertificateFile /srv/#{@domain}/config/ssl.combined"
    end

    #
    # OK we might have the combined values in "ssl.key", or we might
    # have "ssl.key" + "ssl.cert"
    #
    # If both the latter exist we'll treat them separately.
    #
    if ( File.exists?( "/srv/#{@domain}/config/ssl.key" ) &&
         File.exists?( "/srv/#{@domain}/config/ssl.cert" ) )

      return "SSLCertificateFile /srv/#{@domain}/config/ssl.key\nSSLCertificateKeyFile /srv/#{@domain}/config/ssl.cert"
    end

    #
    #  We hope like hell we have ssl.key which is a combined one.
    #
    if ( File.exists?( "/srv/#{@domain}/config/ssl.key" ) )
      return "SSLCertificateFile /srv/#{@domain}/config/ssl.key"
    end

    ""
  end



  #
  # Update Apache to create a site for this domain.
  #
  def create_ssl_site

    template = ERB.new <<-EOF
####
##
#
# DO NOT EDIT THIS FILE - CHANGES WILL BE OVERWRITTEN
#
#  This file is automatically generated.
#
#  http://symbiosis.bytemark.co.uk/docs/ch-ssl-hosting.html
#
##
###

NameVirtualHost $ip:443

<VirtualHost <%= ip() %>:443>

        SSLEngine On
        <%= certificate %>
        <%= bundle() %>
        $bundle
        SSLOptions +StrictRequire


        #
        #  This is the directory people are redirected to
        # if their site is empty.
        #
        Alias /bytemark/ "/usr/share/symbiosis-static/"
        <Directory "/usr/share/symbiosis-static/">
                DirectoryIndex index.html
                AllowOverride None
        </Directory>

        #
        #  Allow users to override settings via .htaccess
        #
        <Directory "/srv">
                AllowOverride all
        </Directory>

        #
        #  And this makes that redirection happen.
        #
        <LocationMatch "^/+$">
                Options -Indexes
                ErrorDocument 403 /bytemark/
        </LocationMatch>

        #
        #  The document root
        #
        DocumentRoot     /srv/<%= @domain %>/public/htdocs/

        #
        # General CGI Handling
        #
        ScriptAlias /cgi-bin/ /srv/<%= @domain %>/public/cgi-bin/
        <Location /cgi-bin>
                Options +ExecCGI
        </Location>



        #
        #  We need to log the virtual hostname the incoming request was
        # made against, so that the cron-job in /etc/cron.daily may generate
        # statistics for each domain.
        #
        ErrorLog   /var/log/apache2/<%= @domain %>.ssl.error.log
        CustomLog  /var/log/apache2/<%= @domain %>.ssl.access.log combined
</VirtualHost>



NameVirtualHost <%= ip() %>:80

<VirtualHost <%= ip() %>:80>

<% if mandatory_ssl? %>
        #
        #  All accesses redirect to the HTTPS version of
        # the site.
        #
        Redirect / https://<%= @domain %>/

<% else %>

        #
        #  This is the directory people are redirected to
        # if their site is empty.
        #
        Alias /bytemark/ "/usr/share/symbiosis-static/"
        <Directory "/usr/share/symbiosis-static/">
                DirectoryIndex index.html
                AllowOverride None
        </Directory>

        #
        #  Allow users to override settings via .htaccess
        #
        <Directory "/srv">
                AllowOverride all
        </Directory>

        #
        #  And this makes that redirection happen.
        #
        <LocationMatch "^/+$">
                Options -Indexes
                ErrorDocument 403 /bytemark/
        </LocationMatch>

        #
        #  The document root
        #
        DocumentRoot     /srv/$domain/public/htdocs/

        #
        # General CGI Handling
        #
        ScriptAlias /cgi-bin/ /srv/<%= @domain %>/public/cgi-bin/
        <Location /cgi-bin>
                Options +ExecCGI
        </Location>



        #
        #  We need to log the virtual hostname the incoming request was
        # made against, so that the cron-job in /etc/cron.daily may generate
        # statistics for each domain.
        #
        ErrorLog   /var/log/apache2/<%= @domain %>.error.log
        CustomLog  /var/log/apache2/<%= @domain %>.access.log combined
<% end %>
</VirtualHost>


EOF

    #
    # Write out to sites-enabled
    #
    File.open( "/etc/apache2/sites-available/#{@domain}.ssl", "w" ) do |file|
      file.write template.result(binding)
    end

    #
    #  Now link in the file
    #
    File.symlink( "/etc/apache2/sites-available/#{@domain}.ssl",
                  "/etc/apache2/sites-enabled/#{@domain}.ssl" )

  end



  #
  # Does the SSL site need updating because a file is more
  # recent than the generated Apache site?
  #
  def outdated?

    #
    # creation time of the (previously generated) SSL-site.
    #
    site = File.ctime( "/etc/apache2/sites-available/#{@domain}.ssl" )


    #
    #  For each configuration file see if it is more recent
    #
    files = %w( ssl.combined ssl.key ssl.bundle ip )

    files.each do |file|
      if ( File.exists?( "/srv/#{@domain}/config/#{file}" ) )
        ctime = File.ctime("/srv/#{@domain}/config/#{file}" )
        if ( ctime > site )
          return true
        end
      end
    end

    false
  end

end




#
#  Entry point to the code
#
if __FILE__ == $0 then

  $VERBOSE = false
  $HELP    = false

  opts = GetoptLong.new(
                        [ '--help', '-h', GetoptLong::NO_ARGUMENT ],
                        [ '--verbose', '-v', GetoptLong::NO_ARGUMENT ]
                        )


  opts.each do |opt, arg|
    case opt
    when '--help'
      $HELP = true
    when '--verbose'
      $VERBOSE = true
    end
  end

  #
  # CAUTION! Here be quality kode.
  #
  if $HELP
    # Open the file, stripping the shebang line
    lines = File.open(__FILE__){|fh| fh.readlines}[2..-1]

    lines.each do |line|
      line.chomp!
      break if line.empty?
      puts line[2..-1].to_s
    end

    exit 0
  end

  #
  # Ensure we're root
  #
  if ( ENV['USER'] != "root" )
    puts "You must run this script as root"
  end

  #
  #  Do we need to restart apache?
  #
  $RESTART=false

  #
  #  For each domain.
  #
  helper = Symbiosis::Domains.new()
  helper.domains.each do |domain|


    puts "Domain: #{domain} " if ( $VERBOSE )

    #
    #  Create a helper for the domain.
    #
    helper = SSLConfiguration.new( domain )

    #
    #  If SSL is not enabled then we can skip
    #
    if ( helper.ssl_enabled? )

      puts "\tSSL is enabled" if ( $VERBOSE )

      #
      #  If there is already a site enabled we only
      # need to touch it if one of the SSL-files is more
      # recent than the generated file.
      #
      #  e.g. User adds /config/ssl.combined and a site
      # is generated but broken because a mandatory bundle is missing.
      #
      if ( helper.site_enabled? )

        puts "\tSite already present" if ( $VERBOSE )

        if ( helper.outdated? )

          puts "\tRecreating as it is older than the input file(s)" if ( $VERBOSE )
          helper.remove_site()
          helper.create_ssl_site()
          $RESTART = true
        else

          puts "\tLeaving as-is" if ( $VERBOSE )
        end
      else

        puts "\tSite not already present" if ( $VERBOSE )

        #
        # Create site.
        #
        helper.create_ssl_site()

        $RESTART=true
      end

    else
      puts "\tSSL is not enabled" if ( $VERBOSE )

    end
  end

  #
  #  All done.
  #
  if ( $RESTART )
    puts "Restarting Apache" if ( $VERBOSE )

    system( "/etc/init.d/apache2 restart" )
  end
end
