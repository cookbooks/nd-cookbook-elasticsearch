include_recipe 'aws'

data_bag_key = Chef::EncryptedDataBagItem.load_secret(node['data_bag_key'])
secrets = begin
			Chef::EncryptedDataBagItem.load("secrets", node.chef_environment, data_bag_key)
		  rescue => e
        Chef::Log.error("Failed to load secrets data bag: "+ e.inspect)
        { "aws" => { "elasticsearch" => { "access_key_id" => nil, "secret_access_key" => nil } } }
      end

case node.elasticsearch[:cluster_name]
when "elasticsearch"
	nametag = "ElasticSearch (#{node.chef_environment})"
else
	nametag = "ElasticSearch (#{node.chef_environment}): #{node.elasticsearch[:cluster_name]}"
end

if node.has_key?('ec2')
	aws_resource_tag node['ec2']['instance_id'] do
		aws_access_key secrets['aws']['elasticsearch']['access_key_id']
		aws_secret_access_key secrets['aws']['elasticsearch']['secret_access_key']
		tags({
				"Name" => nametag,
				"Environment" => node.chef_environment,
				"ElasticSearchCluster" => node.elasticsearch[:cluster_name]
			})
		action :update
	end
end

install_plugin "elasticsearch/elasticsearch-cloud-aws/#{node.elasticsearch[:plugin][:aws][:version]}"
