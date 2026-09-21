-- Enable members to update their own organization profile
CREATE POLICY "Members can update their organizations" 
ON organizations
FOR UPDATE 
USING (is_org_member(id));
