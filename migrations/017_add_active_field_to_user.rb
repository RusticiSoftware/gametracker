Sequel.migration do

  up do
    alter_table :players do
      add_column :active, TrueClass, :default => true
    end
  end

  down do
    alter_table :players do
      drop_column :active
    end
  end

end
