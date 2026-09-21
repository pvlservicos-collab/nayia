import { createClient } from '@supabase/supabase-js'

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL!
const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!

const supabase = createClient(supabaseUrl, supabaseKey)

async function main() {
    const { data: orgs } = await supabase.from('organizations').select('*')
    console.log('Todas as Organizações:', orgs)

    const { data: profiles } = await supabase.from('profiles').select('*')
    console.log('Perfis:', profiles)

    const { data: members } = await supabase.from('organization_members').select('*')
    console.log('Membros de Org:', members)
}

main()
