module Elasticity

  class InstanceTypeConfig

    attr_accessor :bid_price
    attr_accessor :type
    attr_accessor :weighted_capacity

    def initialize
      @bid_price = nil
      @type = 'm1.small'
    end

    def ebs=(ebs_opts = {})
      @ebs = Elasticity::EBSConfiguration.from_opts(ebs_opts)
    end

    def to_aws_instance_config
      {
        :instance_type => @type,
      }.tap do |config|
        config.merge!(:ebs_configuration => @ebs) if @ebs
        config.merge!(:bid_price => @bid_price) if @bid_price
        config.merge!(:weighted_capacity => @weighted_capacity) if @weighted_capacity
      end
    end

  end

end
