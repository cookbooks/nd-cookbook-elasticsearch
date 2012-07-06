elasticsearch = "elasticsearch-#{node.elasticsearch[:version]}"

data_bag_key = Chef::EncryptedDataBagItem.load_secret(node['data_bag_key'])
secrets = begin
      Chef::EncryptedDataBagItem.load("secrets", node.chef_environment, data_bag_key)
      rescue => e
        Chef::Log.error("Failed to load secrets data bag: "+ e.inspect)
        { "aws" => { "elasticsearch" => { "access_key_id" => nil, "secret_access_key" => nil } } }
      end

unless node.elasticsearch[:cloud][:aws][:access_key] and node.elasticsearch[:cloud][:aws][:secret_key]
  @aws = {
    "access_key" => secrets['aws']['elasticsearch']['access_key_id'],
    "secret_key" => secrets['aws']['elasticsearch']['secret_access_key']
  }
else
  @aws = {
    "access_key" => node.elasticsearch[:cloud][:aws][:access_key],
    "secret_key" => node.elasticsearch[:cloud][:aws][:secret_key]
  }
end

# Include the `curl` recipe, needed by `service status`
#
include_recipe "java"
include_recipe "elasticsearch::curl"
include_recipe "ark"
include_recipe "logrotate"

# Create user and group
#
group node.elasticsearch[:user] do
  action :create
end

user node.elasticsearch[:user] do
  comment "ElasticSearch User"
  home    "#{node.elasticsearch[:dir]}/elasticsearch"
  shell   "/bin/bash"
  gid     node.elasticsearch[:user]
  supports :manage_home => false
  action  :create
end

# FIX: Work around the fact that Chef creates the directory even for `manage_home: false`
bash "remove the elasticsearch user home" do
  user    'root'
  code    "rm -rf  #{node.elasticsearch[:dir]}/elasticsearch"
  only_if "test -d #{node.elasticsearch[:dir]}/elasticsearch"
end

ark "elasticsearch" do
  url "https://github.com/downloads/elasticsearch/elasticsearch/#{elasticsearch}.tar.gz"
  owner node.elasticsearch[:user]
  group node.elasticsearch[:user]
  version node.elasticsearch[:version]
  has_binaries ['bin/elasticsearch', 'bin/plugin' ]
  checksum node.elasticsearch[:checksum]
end

# Create ES directories
#
%w| conf_path data_path log_path pid_path |.each do |path|
  directory node.elasticsearch[path.to_sym] do
    owner node.elasticsearch[:user] and group node.elasticsearch[:user] and mode 0755
    recursive true
    action :create
  end
end

# Create service
#
template "/etc/init.d/elasticsearch" do
  source "elasticsearch.init.erb"
  owner 'root' and mode 0755
end

service "elasticsearch" do
  supports :status => true, :restart => true
  action [ :enable ]
end

# Download, extract, symlink the elasticsearch libraries and binaries
#
ark "elasticsearch" do
  url "https://github.com/downloads/elasticsearch/elasticsearch/#{elasticsearch}.tar.gz"
  owner node.elasticsearch[:user]
  group node.elasticsearch[:user]
  version node.elasticsearch[:version]
  has_binaries ['bin/elasticsearch', 'bin/plugin']
  checksum node.elasticsearch[:checksum]

  notifies :restart, resources(:service => 'elasticsearch')
end

# Increase open file limits
#
bash "enable user limits" do
  user 'root'

  code <<-END.gsub(/^    /, '')
    echo 'session    required   pam_limits.so' >> /etc/pam.d/su
  END

  not_if { ::File.read("/etc/pam.d/su").match(/^session    required   pam_limits\.so/) }
end

bash "increase limits for the elasticsearch user" do
  user 'root'

  code <<-END.gsub(/^    /, '')
    echo '#{node.elasticsearch.fetch(:user, "elasticsearch")}     -    nofile    #{node.elasticsearch[:limits][:nofile]}'  >> /etc/security/limits.conf
    echo '#{node.elasticsearch.fetch(:user, "elasticsearch")}     -    memlock   #{node.elasticsearch[:limits][:memlock]}' >> /etc/security/limits.conf
  END

  not_if { ::File.read("/etc/security/limits.conf").include?("#{node.elasticsearch.fetch(:user, "elasticsearch")}     -    nofile")  }
end


# Create file with ES environment variables
#
template "elasticsearch-env.sh" do
  path   "#{node.elasticsearch[:conf_path]}/elasticsearch-env.sh"
  source "elasticsearch-env.sh.erb"
  owner node.elasticsearch[:user] and group node.elasticsearch[:user] and mode 0755

  notifies :restart, resources(:service => 'elasticsearch')
end

# Create ES config file
#
template "elasticsearch.yml" do
  path   "#{node.elasticsearch[:conf_path]}/elasticsearch.yml"
  source "elasticsearch.yml.erb"
  owner node.elasticsearch[:user] and group node.elasticsearch[:user] and mode 0755
  variables({ :aws => @aws })

  notifies :restart, resources(:service => 'elasticsearch')
end

# Add Monit configuration file
#
if node.recipes.include?('monit')
  monitrc("elasticsearch",
          :pidfile => "#{node.elasticsearch[:pid_path]}/#{node.elasticsearch[:node_name].to_s.gsub(/\W/, '_')}.pid")
else
  # ... if we aren't using monit, let's reopen the elasticsearch service and start it
  service("elasticsearch") { action :start }
end

logrotate_app "elasticsearch" do
  path "#{node['elasticsearch']['log_path']}/*.log"
  frequency "daily"
  create    "664 #{node['elasticsearch']['user']} #{node['elasticsearch']['user']}"
  rotate "30"
end
