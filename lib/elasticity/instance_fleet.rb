module Elasticity

  class InstanceFleet

    MAX_NUM_INSTANCE_TYPES = 5
    ROLES = %w(MASTER CORE TASK)
    TIMEOUT_ACTIONS = %w(SWITCH_TO_ON_DEMAND TERMINATE_CLUSTER)
    MIN_PROVISIONING_TIMEOUT_MINUTES = 5
    MAX_PROVISIONING_TIMEOUT_MINUTES = 1440
    VALID_BLOCK_DURATION_MINUTES = [60, 120, 180, 240, 300, 360]

    attr_accessor :role
    attr_accessor :name
    attr_accessor :target_on_demand_capacity
    attr_accessor :target_spot_capacity
    attr_accessor :spot_block_duration_minutes
    attr_accessor :spot_provisioning_timeout_minutes
    attr_accessor :spot_provisioning_timeout_action

    def initialize
      @instance_type_configs = []
      @role = 'CORE'
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
        raise ArgumentError, "Role must be one of #{ROLES.join(', ')} (#{group_role} was requested)."
      end
      @role = group_role
    end

    def name=(group_name)
      @name = group_name
    end

    def spot_provisioning_timeout_action=(action)
      if !TIMEOUT_ACTIONS.include?(action)
        raise ArgumentError, "Timeout action must be one of #{TIMEOUT_ACTIONS.join(', ')} (#{action} was requested)."
      end
      @spot_provisioning_timeout_action = action
    end

    def spot_provisioning_timeout_minutes=(timeout_minutes)
      if !(MIN_PROVISIONING_TIMEOUT_MINUTES..MAX_PROVISIONING_TIMEOUT_MINUTES).include?(timeout_minutes)
        raise ArgumentError, 'Timeout minutes must be in ' \
          "[#{MIN_PROVISIONING_TIMEOUT_MINUTES}, #{MAX_PROVISIONING_TIMEOUT_MINUTES}] " \
          "(#{timeout_minutes} was requested)."
      end
      @spot_provisioning_timeout_minutes = timeout_minutes
    end

    def spot_block_duration_minutes=(duration_minutes)
      if !VALID_BLOCK_DURATION_MINUTES.include?(duration_minutes)
        raise ArgumentError, "Bock duration minutes must be in #{VALID_BLOCK_DURATION_MINUTES.join(', ')} "
          "(#{duration_minutes} was requested)."
      end
      @spot_block_duration_minutes = duration_minutes
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
        raise ArgumentError, 'Capacity must be set to one for MASTER instance fleet.'
      end

      spot_specification = {}
      spot_specification[:block_duration_minutes] = @spot_block_duration_minutes if @spot_block_duration_minutes
      spot_specification[:timeout_action] = @spot_provisioning_timeout_action if @spot_provisioning_timeout_action
      spot_specification[:timeout_duration_minutes] = @spot_provisioning_timeout_minutes if @spot_provisioning_timeout_minutes

      if !spot_specification.empty?
        if spot_specification[:timeout_action].nil? || spot_specification[:timeout_duration_minutes].nil?
          raise ArgumentError, 'Provisioning timeout and timeout action are required for spot fleet launch specification!'
        end
      end

      {
        :instance_fleet_type => @role,
        :instance_type_configs => @instance_type_configs.map(&:to_aws_instance_config),
        :name => @name || "#{@role}-#{object_id}",  # default to role-objectid to differentiate duplicates
        :target_on_demand_capacity => @target_on_demand_capacity,
        :target_spot_capacity => @target_spot_capacity
      }.tap do |config|
        if !spot_specification.empty?
          config[:launch_specifications] = {}
          config[:launch_specifications][:spot_specification] = spot_specification
        end
      end
    end

  end

end
