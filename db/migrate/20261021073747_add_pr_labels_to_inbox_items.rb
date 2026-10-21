class AddPrLabelsToInboxItems < ActiveRecord::Migration[8.1]
  def change
    add_column :inbox_items, :pr_labels, :json, default: [], null: false
  end
end
