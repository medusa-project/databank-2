class BackfillCreatorInstitutionNameFromName < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      UPDATE creators
      SET institution_name = name
      WHERE COALESCE(TRIM(institution_name), '') = ''
        AND COALESCE(TRIM(name), '') <> ''
        AND COALESCE(TRIM(given_name), '') = ''
        AND COALESCE(TRIM(family_name), '') = '';
    SQL
  end

  def down
    execute <<~SQL
      UPDATE creators
      SET institution_name = NULL
      WHERE institution_name = name
        AND COALESCE(TRIM(given_name), '') = ''
        AND COALESCE(TRIM(family_name), '') = '';
    SQL
  end
end
