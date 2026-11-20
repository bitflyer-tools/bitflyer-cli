# frozen_string_literal: true

require 'thor'

module OrderAmount
  def self.validate!(amount)
    raise Thor::Error, 'Amount must be positive and finite.' unless amount.positive? && amount.finite?

    amount
  end
end
