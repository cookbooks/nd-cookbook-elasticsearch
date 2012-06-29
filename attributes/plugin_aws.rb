# Load configuration and credentials from data bag 'elasticsearch/aws' -
#
data_bag_key = Chef::EncryptedDataBagItem.load_secret(node['data_bag_key'])
secrets = Chef::EncryptedDataBagItem.load("secrets", node.chef_environment, data_bag_key)

aws = secrets['aws'] rescue {}
# ----------------------------------------------------------------------

default.elasticsearch[:plugin][:aws][:version] = '1.5.0'

# === AWS ===
# AWS configuration is set based on data bag values.
# You may choose to configure them in your node configuration instead.
#
default.elasticsearch[:gateway][:type]               = ( aws['gateway']['type']                rescue nil )
default.elasticsearch[:discovery][:type]             = ( aws['discovery']['type']              rescue nil )
default.elasticsearch[:gateway][:s3][:bucket]        = ( aws['gateway']['s3']['bucket']        rescue nil )

default.elasticsearch[:cloud][:ec2][:security_group] = ( aws['cloud']['ec2']['security_group'] rescue nil )
default.elasticsearch[:cloud][:aws][:access_key]     = ( aws['aws_access_key_id']     rescue nil )
default.elasticsearch[:cloud][:aws][:secret_key]     = ( aws['aws_secret_access_key']     rescue nil )
