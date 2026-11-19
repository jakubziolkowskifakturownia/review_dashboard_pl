# Wybór list zadań nad kolejką staje się wielokrotny — jedna wybrana lista przechodzi do tablicy.
class ChangeInboxTasklistIdToIdsOnProjects < ActiveRecord::Migration[8.1]
  def up
    add_column :projects, :inbox_tasklist_ids, :json, default: [], null: false
    execute <<~SQL
      UPDATE projects SET inbox_tasklist_ids = json_array(inbox_tasklist_id)
      WHERE inbox_tasklist_id IS NOT NULL AND inbox_tasklist_id != ''
    SQL
    remove_column :projects, :inbox_tasklist_id
  end

  def down
    add_column :projects, :inbox_tasklist_id, :string
    execute "UPDATE projects SET inbox_tasklist_id = json_extract(inbox_tasklist_ids, '$[0]')"
    remove_column :projects, :inbox_tasklist_ids
  end
end
