# Cache list zadań z trackera: numer zadania → listy (cykl, backlog…). Strona
# wejściowa czyta tylko stąd — tracker odpytuje wyłącznie RefreshTrackerTasksJob.
class CreateTrackerTasks < ActiveRecord::Migration[8.1]
  def change
    create_table :tracker_tasks do |t|
      t.references :project, null: false, foreign_key: true
      t.string :number, null: false
      t.json :lists, null: false, default: []
      t.datetime :fetched_at
      t.timestamps
    end
    add_index :tracker_tasks, %i[project_id number], unique: true
  end
end
