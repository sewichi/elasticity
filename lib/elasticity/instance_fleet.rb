require 'set'

module Elasticity

  class InstanceFleet

    MAX_NUM_INSTANCE_TYPES = 5
    ROLES = %w(MASTER CORE TASK)

    attr_accessor :role
    attr_accessor :name
    attr_accessor :target_on_demand_capacity
    attr_accessor :target_spot_capacity

    def initialize
      @instance_type_configs = []
      @role = 'CORE'
      @name = nil
      @target_on_demand_capacity = 0
      @target_spot_capacity = 0
    end

    def check_capacity(capacity)
      if capacity <= 0
        raise ArgumentError, "Instance fleets require capacity at least 1! (#{capacity} requested)"
      end
      if @role == 'MASTER' && capacity != 1
        raise ArgumentError, "MASTER instance fleets can only have capacity 1! (#{capacity} requested)"
      end
    end

    def target_on_demand_capacity=(capacity)
      check_capacity(capacity)
      @target_on_demand_capacity = capacity
    end

    def target_spot_capacity=(capacity)
      check_capacity(capacity)
      @target_spot_capacity = capacity
    end

    def role=(group_role)
      if !ROLES.include?(group_role)
        raise ArgumentError, "Role must be one of MASTER, CORE or TASK (#{group_role} was requested)"
      end
      @role = group_role
    end

    def name=(group_name)
      @name = group_name
    end

    def add_instance_type_config(config)
      if @instance_type_configs.length >= MAX_NUM_INSTANCE_TYPES
        raise ArgumentError, "Only #{MAX_NUM_INSTANCE_TYPES} instance types allowed per instance fleet!"
      else
        @instance_type_configs << config
      end
    end

    def to_aws_instance_config
      if @role == 'MASTER' && Set[@target_on_demand_capacity, @target_spot_capacity] != Set[0, 1]
        raise ArgumentError, "Capacity must be set to one for MASTER instance fleet."
      end

      {
        :instance_fleet_type => @role,
        :instance_type_configs => @instance_type_configs.map(&:to_aws_instance_config),
        :name => @name || "#{@role}-#{object_id}",  # default to role-objectid to differentiate duplicates
        :target_on_demand_capacity => @target_on_demand_capacity,
        :target_spot_capacity => @target_spot_capacity
      }
    end

  end

end
