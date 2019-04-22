module Elasticity

  class InstanceGroup

    ROLES = Elasticity::InstanceConstraints::VALID_INSTANCE_COLLECTION_ROLES

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
      @ebs = Elasticity::EBSConfiguration.from_opts(ebs_opts)
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
