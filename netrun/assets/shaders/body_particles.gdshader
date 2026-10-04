// Чужие руки и голова (client/avatar_body.gd): то же облако точек, что у своих рук (particles_body.gdshaderinc), но с проверкой глубины —
// стены, плитки и сами игроки закрывают аватар, как и положено телу в комнате. Аддитивно, без освещения.
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, fog_disabled;

#include "particles_body.gdshaderinc"
