-- Database constraints for branch_users table
-- Ensures at least one owner exists per branch

-- Function to check if at least one owner exists for a branch
CREATE OR REPLACE FUNCTION check_at_least_one_owner()
RETURNS TRIGGER AS $$
DECLARE
  owner_count INTEGER;
  branch_uuid UUID;
BEGIN
  -- Determine which branch we're working with
  IF TG_OP = 'DELETE' THEN
    branch_uuid := OLD.branch_id;
  ELSE
    branch_uuid := NEW.branch_id;
  END IF;

  -- Count owners for this branch after the operation
  IF TG_OP = 'DELETE' AND OLD.role = 'owner' THEN
    -- Check if this was the last owner
    SELECT COUNT(*) INTO owner_count
    FROM branch_users
    WHERE branch_id = branch_uuid
      AND role = 'owner'
      AND id != OLD.id;
    
    IF owner_count = 0 THEN
      RAISE EXCEPTION 'Cannot delete the last owner. A branch must have at least one owner.';
    END IF;
  ELSIF TG_OP = 'UPDATE' AND OLD.role = 'owner' AND NEW.role != 'owner' THEN
    -- Check if changing from owner to non-owner would leave no owners
    SELECT COUNT(*) INTO owner_count
    FROM branch_users
    WHERE branch_id = branch_uuid
      AND role = 'owner'
      AND id != NEW.id;
    
    IF owner_count = 0 THEN
      RAISE EXCEPTION 'Cannot change role. A branch must have at least one owner.';
    END IF;
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

-- Drop trigger if exists
DROP TRIGGER IF EXISTS enforce_at_least_one_owner ON branch_users;

-- Create trigger to enforce the constraint
CREATE TRIGGER enforce_at_least_one_owner
  BEFORE DELETE OR UPDATE ON branch_users
  FOR EACH ROW
  EXECUTE FUNCTION check_at_least_one_owner();

-- Add comment
COMMENT ON FUNCTION check_at_least_one_owner() IS 'Ensures that each branch has at least one owner. Prevents deletion or role change of the last owner.';

