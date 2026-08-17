-- Fix: get_advisors(security) detectó que anon podía ejecutar marcar_canje_pagado
-- via RPC (grant directo a anon, no vía PUBLIC como en el caso anterior -- Supabase
-- aparentemente otorga privilegios distintos según el momento/rol de creación). Se
-- revoca explícitamente de public, anon y authenticated, y se vuelve a otorgar solo a
-- authenticated (la guarda real sigue siendo el chequeo de admins dentro de la función,
-- esto es defensa adicional para que ni siquiera un authenticated sin pasar por el panel
-- pueda invocarla a ciegas -- aunque igual recibiría 'No autorizado' si no está en admins).

revoke execute on function public.marcar_canje_pagado(text) from public, anon, authenticated;
grant execute on function public.marcar_canje_pagado(text) to authenticated;
