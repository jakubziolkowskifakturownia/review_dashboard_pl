class AddInboxTasklistIdToProjects < ActiveRecord::Migration[8.1]
  def change
    add_column :projects, :inbox_tasklist_id, :string
  end
end
