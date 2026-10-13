# An order and its items. Prices are frozen when the order is paid.
class Order < ApplicationRecord
  STATUSES = %w[new paid shipped cancelled].freeze

  belongs_to :customer
  has_many :items, class_name: "OrderItem", dependent: :destroy

  validates :status, inclusion: { in: STATUSES }
  scope :recent, -> { where(created_at: 30.days.ago..).order(created_at: :desc) }

  def total
    items.sum { |item| item.quantity * item.unit_price }
  end

  def pay!(payment)
    transaction do
      items.each(&:freeze_price!)
      update!(status: "paid", paid_at: Time.current, payment_ref: payment.ref)
    end
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.warn("order #{id} not paid: #{e.message}")
    false
  end

  def shipped?
    status == "shipped"
  end
end
