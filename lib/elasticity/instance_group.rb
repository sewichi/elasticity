module Elasticity

  class InstanceGroup

    ROLES = %w(MASTER CORE TASK)

    attr_accessor :count
    attr_accessor :type
    attr_accessor :role
    attr_accessor :ebs
    attr_accessor :bid_price
    attr_accessor :name

    attr_reader :bid_price
    attr_reader :market

    def initialize
      @count = 1
      @type = 'm1.small'
      @market = 'ON_DEMAND'
      @role = 'CORE'
      @ebs = nil
      @name = nil
    end

    def ebs=(ebs_opts = {})
      if (ebs_opts[:ebs_size_in_gb].nil? || ebs_opts[:ebs_optimized].nil? || ebs_opts[:ebs_volume_type].nil? || ebs_opts[:ebs_number_of_volumes].nil?)
        raise ArgumentError, "Missing EBS parameters. Passed: #{ebs_opts}"
      end

      ebs_opts[:ebs_size_in_gb] = ebs_opts[:ebs_size_in_gb].to_i
      if ebs_opts[:ebs_iops]
        ebs_opts[:ebs_iops] = ebs_opts[:ebs_iops].to_i
      end

      ebs_opts[:ebs_number_of_volumes] = ebs_opts[:ebs_number_of_volumes].to_i

      if ebs_opts[:ebs_size_in_gb] <= 0
        raise ArgumentError, "EBS Size must be at least 0 to add an EBS volume (#{ebs_opts[:ebs_size_in_gb]} requested)"
      end

      if ebs_opts[:ebs_number_of_volumes] < 1
        raise ArgumentError, "Must have at least one EBS volume (#{ebs_opts[:ebs_number_of_volumes]} requested)"
      end

      if ebs_opts[:ebs_size_in_gb] >= 1024
        raise ArgumentError, "EBS Size must be less than 1024 to add an EBS volume (#{ebs_opts[:ebs_size_in_gb]} requested)"
      end

      if ebs_opts[:ebs_optimized] && ebs_opts[:ebs_size_in_gb] < 10
        raise ArgumentError, "EBS Size must be at least 10 if ebs_optimized (#{ebs_opts[:ebs_size_in_gb]} requested)"
      end

      if !['gp2','io1','standard','st1','sc1'].include?(ebs_opts[:ebs_volume_type])
        raise ArgumentError, "EBS Volume Type is not a supported type (#{ebs_opts[:ebs_volume_type]} requested)"
      end

      if ebs_opts[:ebs_volume_type] == 'io1'
        if ebs_opts[:ebs_iops].nil?
          raise ArgumentError, "#{ebs_opts[:ebs_volume_type]} volume type requires iops to be set"
        end
      elsif ebs_opts[:ebs_iops]
        raise ArgumentError, "Iops not supported with #{ebs_opts[:ebs_volume_type]} volume type"
      end

      volume_specification = {
        :volume_type => ebs_opts[:ebs_volume_type],
        :size_in_GB => ebs_opts[:ebs_size_in_gb]
      }

      if ebs_opts[:ebs_iops]
        volume_specification[:iops] = ebs_opts[:ebs_iops]
      end

      @ebs = {
        :ebs_block_device_configs => [
              {
                :volumes_per_instance => ebs_opts[:ebs_number_of_volumes],
                :volume_specification => volume_specification
              }
            ],
        :ebs_optimized => ebs_opts[:ebs_optimized]
      }

    end

    def count=(instance_count)
      if instance_count <= 0
        raise ArgumentError, "Instance groups require at least 1 instance (#{instance_count} requested)"
      end
      if @role == 'MASTER' && instance_count != 1
        raise ArgumentError, "MASTER instance groups can only have 1 instance (#{instance_count} requested)"
      end
      @count = instance_count
    end

    def role=(group_role)
      if !ROLES.include?(group_role)
        raise ArgumentError, "Role must be one of MASTER, CORE or TASK (#{group_role} was requested)"
      end
      @count = 1 if group_role == 'MASTER'
      @role = group_role
    end

    def name=(group_name)
      @name = group_name
    end

    def set_spot_instances(bid_price)
      if bid_price < 0
        raise ArgumentError, "The bid price for spot instances should be greater than 0 (#{bid_price} requested)"
      end
      @bid_price = bid_price
      @market = 'SPOT'
    end

    def set_on_demand_instances
      @bid_price = nil
      @market = 'ON_DEMAND'
    end

    def to_aws_instance_config
      {
        :market => @market,
        :instance_count => @count,
        :instance_type => @type,
        :instance_role => @role,
        :name => @name || "#{@role}-#{object_id}"  # default to role-objectid to differentiate duplicates
      }.tap do |config|
        config.merge!(:ebs_configuration => @ebs) if @ebs
        config.merge!(:bid_price => @bid_price) if @market == 'SPOT'
      end
    end

  end

end
