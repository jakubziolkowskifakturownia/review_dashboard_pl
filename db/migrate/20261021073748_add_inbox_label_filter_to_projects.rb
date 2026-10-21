class AddInboxLabelFilterToProjects < ActiveRecord::Migration[8.1]
  def change
    add_column :projects, :inbox_shown_labels, :json, default: [], null: false
    add_column :projects, :inbox_hidden_labels, :json, default: [], null: false
  end
end
