from __future__ import annotations

import math
from dataclasses import dataclass, field
from datetime import datetime, timezone
from enum import Enum

from .clustering import EARTH_RADIUS_M
from .scoring import FUERZA_TAREA, RECONOCIMIENTO


class ResourceClass(str, Enum):
    RECURSO_SIMPLE = "RECURSO_SIMPLE"
    EQUIPO_INTERVENCION = "EQUIPO_INTERVENCION"
    FUERZA_TAREA = "FUERZA_TAREA"


class ResourceCategory(str, Enum):
    MEDICO = "MEDICO"
    RESCATE_URBANO = "RESCATE_URBANO"
    BOMBEROS = "BOMBEROS"
    RECONOCIMIENTO = "RECONOCIMIENTO"
    MAQUINARIA_PESADA = "MAQUINARIA_PESADA"
    SEGURIDAD = "SEGURIDAD"
    LOGISTICA = "LOGISTICA"


class ResourceStatus(str, Enum):
    DISPONIBLE = "DISPONIBLE"
    ASIGNADO = "ASIGNADO"
    NO_DISPONIBLE = "NO_DISPONIBLE"


class IncidentLifecycleStatus(str, Enum):
    PENDIENTE = "PENDIENTE"
    EN_ATENCION = "EN_ATENCION"
    RESUELTO = "RESUELTO"
    FALSA_ALARMA = "FALSA_ALARMA"


class RouteStatus(str, Enum):
    LIBRE = "LIBRE"
    DESVIO_POR_BLOQUEO = "DESVIO_POR_BLOQUEO"
    BLOQUEADA = "BLOQUEADA"


URBAN_DETOUR_FACTOR = 1.3
DEFAULT_SPEED_KMH = 45.0

KIND_COMPATIBILITY: dict[str, set[ResourceCategory]] = {
    "DERRUMBE": {
        ResourceCategory.RESCATE_URBANO,
        ResourceCategory.MAQUINARIA_PESADA,
        ResourceCategory.MEDICO,
    },
    "PERSONA_ATRAPADA": {
        ResourceCategory.RESCATE_URBANO,
        ResourceCategory.MEDICO,
        ResourceCategory.BOMBEROS,
    },
    "INUNDACION": {
        ResourceCategory.RESCATE_URBANO,
        ResourceCategory.LOGISTICA,
        ResourceCategory.MEDICO,
    },
    "INCENDIO": {
        ResourceCategory.BOMBEROS,
        ResourceCategory.MEDICO,
        ResourceCategory.LOGISTICA,
    },
    "HERIDO_GRAVE": {
        ResourceCategory.MEDICO,
        ResourceCategory.RESCATE_URBANO,
    },
}


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


@dataclass
class Resource:
    id: int
    code: str
    name: str
    resource_class: ResourceClass
    resource_type: int  # SCI Tipo 1 (mayor capacidad) a 4 (ligero)
    category: ResourceCategory
    status: ResourceStatus
    lat: float
    lon: float
    speed_kmh: float = DEFAULT_SPEED_KMH
    capacity: int = 4
    assigned_cluster_id: int | None = None
    leader: str | None = None
    subordinates_count: int = 0

    def __post_init__(self) -> None:
        if not (1 <= self.resource_type <= 4):
            raise ValueError("resource_type SCI-211 debe estar entre 1 y 4")
        if self.speed_kmh <= 0:
            raise ValueError("speed_kmh debe ser mayor a 0")


@dataclass
class RoadBlock:
    id: int
    lat: float
    lon: float
    radius_m: float = 60.0
    severity: int = 8  # 1..10 (10 = corte total)
    description: str = ""
    active: bool = True
    created_at: str = field(default_factory=utc_now_iso)


@dataclass
class RouteEstimate:
    origin_lat: float
    origin_lon: float
    dest_lat: float
    dest_lon: float
    direct_distance_m: float
    effective_distance_m: float
    eta_minutes: float
    status: RouteStatus
    blocking_ids: list[int]
    penalty_factor: float


@dataclass
class IncidentRecord:
    cluster_id: int
    status: IncidentLifecycleStatus = IncidentLifecycleStatus.PENDIENTE
    created_at: str = field(default_factory=utc_now_iso)
    updated_at: str = field(default_factory=utc_now_iso)
    closed_at: str | None = None
    assigned_resource_ids: list[int] = field(default_factory=list)
    notes: str = ""
    commander: str = "COMANDANTE_PC"


@dataclass
class DispatchAuditEntry:
    id: int
    timestamp: str
    actor: str
    action: str
    resource_id: int | None
    cluster_id: int | None
    previous_state: str | None
    new_state: str | None
    details: str


@dataclass
class AssignmentProposal:
    resource_id: int
    resource_code: str
    resource_class: str
    resource_type: int
    category: str
    cluster_id: int
    cluster_urgency: float
    cluster_recommendation: str
    eta_minutes: float
    effective_distance_m: float
    route_status: str
    blocking_ids: list[int]
    score: float


def haversine_m(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lon2 - lon1)
    a = (
        math.sin(dphi / 2.0) ** 2
        + math.cos(phi1) * math.cos(phi2) * math.sin(dlambda / 2.0) ** 2
    )
    return 2.0 * EARTH_RADIUS_M * math.atan2(math.sqrt(a), math.sqrt(max(0.0, 1.0 - a)))


def _point_to_segment_distance_m(
    p_lat: float,
    p_lon: float,
    a_lat: float,
    a_lon: float,
    b_lat: float,
    b_lon: float,
) -> float:
    """Distancia aproximada en metros del punto P al segmento AB usando proyección equirectangular local."""
    mean_lat = math.radians((a_lat + b_lat + p_lat) / 3.0)
    cos_lat = math.cos(mean_lat)
    m_per_deg_lat = 111_320.0
    m_per_deg_lon = 111_320.0 * cos_lat

    ax, ay = 0.0, 0.0
    bx = (b_lon - a_lon) * m_per_deg_lon
    by = (b_lat - a_lat) * m_per_deg_lat
    px = (p_lon - a_lon) * m_per_deg_lon
    py = (p_lat - a_lat) * m_per_deg_lat

    seg_len_sq = bx * bx + by * by
    if seg_len_sq <= 1e-6:
        return math.hypot(px - ax, py - ay)

    t = max(0.0, min(1.0, (px * bx + py * by) / seg_len_sq))
    proj_x = ax + t * bx
    proj_y = ay + t * by
    return math.hypot(px - proj_x, py - proj_y)


def estimate_route(
    origin_lat: float,
    origin_lon: float,
    dest_lat: float,
    dest_lon: float,
    speed_kmh: float = DEFAULT_SPEED_KMH,
    road_blocks: list[RoadBlock] | None = None,
) -> RouteEstimate:
    """Calcula distancia vial estimada, intersección con bloqueos viales y ETA en minutos."""
    direct_m = haversine_m(origin_lat, origin_lon, dest_lat, dest_lon)
    base_road_m = direct_m * URBAN_DETOUR_FACTOR

    active_blocks = [b for b in (road_blocks or []) if b.active]
    intersecting: list[RoadBlock] = []

    for block in active_blocks:
        dist_to_seg = _point_to_segment_distance_m(
            block.lat, block.lon, origin_lat, origin_lon, dest_lat, dest_lon
        )
        if dist_to_seg <= block.radius_m:
            intersecting.append(block)

    if not intersecting:
        speed_m_per_min = (speed_kmh * 1000.0) / 60.0
        eta_min = base_road_m / speed_m_per_min if speed_m_per_min > 0 else 0.0
        return RouteEstimate(
            origin_lat=origin_lat,
            origin_lon=origin_lon,
            dest_lat=dest_lat,
            dest_lon=dest_lon,
            direct_distance_m=round(direct_m, 1),
            effective_distance_m=round(base_road_m, 1),
            eta_minutes=round(eta_min, 2),
            status=RouteStatus.LIBRE,
            blocking_ids=[],
            penalty_factor=0.0,
        )

    max_sev = max(b.severity for b in intersecting)
    extra_detour_m = sum(b.radius_m * (2.5 + 0.3 * b.severity) for b in intersecting)
    effective_m = base_road_m + extra_detour_m

    # Si un bloqueo está encima del destino (dentro de su radio) y es corte total (severidad 10),
    # la ruta directa queda BLOQUEADA; si está en el trayecto, obliga a desvío pesado.
    dest_blocked = any(
        haversine_m(dest_lat, dest_lon, b.lat, b.lon) <= b.radius_m and b.severity >= 10
        for b in intersecting
    )

    penalty_factor = min(1.0, sum(b.severity / 10.0 for b in intersecting) / 2.0)
    effective_speed_kmh = max(8.0, speed_kmh * (1.0 - 0.55 * penalty_factor))
    if dest_blocked:
        effective_speed_kmh = 5.0  # Acceso únicamente a pie / rescate extremo
        status = RouteStatus.BLOQUEADA
    else:
        status = RouteStatus.DESVIO_POR_BLOQUEO

    speed_m_per_min = (effective_speed_kmh * 1000.0) / 60.0
    eta_min = effective_m / speed_m_per_min

    return RouteEstimate(
        origin_lat=origin_lat,
        origin_lon=origin_lon,
        dest_lat=dest_lat,
        dest_lon=dest_lon,
        direct_distance_m=round(direct_m, 1),
        effective_distance_m=round(effective_m, 1),
        eta_minutes=round(eta_min, 2),
        status=status,
        blocking_ids=[b.id for b in intersecting],
        penalty_factor=round(penalty_factor, 2),
    )


def _is_resource_eligible(resource: Resource, recommendation: str) -> bool:
    """
    Regla SCI de despacho en dos fases:
    - Para RECONOCIMIENTO (incertidumbre ciudadana sin verificar): solo se despachan
      unidades rápidas/ligeras (RECONOCIMIENTO, SEGURIDAD, o recursos simples Tipo 3-4).
      Nunca se desvían Fuerzas de Tarea pesadas ni recursos Tipo 1 a alertas no verificadas.
    - Para FUERZA_TAREA (triaje confirmado): cualquier recurso disponible es elegible,
      prefiriendo tipos de mayor capacidad (Tipo 1-2, Fuerza de Tarea / Equipo de Intervención).
    """
    if resource.status != ResourceStatus.DISPONIBLE:
        return False
    if recommendation == RECONOCIMIENTO:
        if resource.resource_class == ResourceClass.FUERZA_TAREA:
            return False
        if resource.resource_type == 1 and resource.category not in {
            ResourceCategory.RECONOCIMIENTO,
            ResourceCategory.SEGURIDAD,
        }:
            return False
        return True
    return True


def _pair_utility(
    resource: Resource,
    cluster_urgency: float,
    cluster_recommendation: str,
    cluster_kinds: list[str],
    route: RouteEstimate,
) -> float:
    """Calcula la utilidad de asignar `resource` al clúster."""
    if not _is_resource_eligible(resource, cluster_recommendation):
        return -1e9

    # 1. Compatibilidad por tipo de emergencia
    compatible_categories: set[ResourceCategory] = set()
    for kind_name in cluster_kinds:
        compatible_categories |= KIND_COMPATIBILITY.get(kind_name, set())

    if cluster_recommendation == RECONOCIMIENTO:
        if resource.category in {ResourceCategory.RECONOCIMIENTO, ResourceCategory.SEGURIDAD}:
            compatibility_bonus = 1.35
        elif resource.resource_type >= 3:
            compatibility_bonus = 1.15
        else:
            compatibility_bonus = 0.85
    else:
        if resource.category in compatible_categories:
            compatibility_bonus = 1.4
        elif resource.category == ResourceCategory.MEDICO:
            compatibility_bonus = 1.2
        else:
            compatibility_bonus = 0.9

    # 2. Factor de capacidad SCI (Tipo 1..4 y Clase)
    if cluster_recommendation == FUERZA_TAREA:
        # En incidentes verificados se premia Tipo 1 y 2 y Fuerzas de Tarea
        type_weight = {1: 1.35, 2: 1.2, 3: 1.0, 4: 0.85}.get(resource.resource_type, 1.0)
        class_bonus = {
            ResourceClass.FUERZA_TAREA: 15.0,
            ResourceClass.EQUIPO_INTERVENCION: 10.0,
            ResourceClass.RECURSO_SIMPLE: 0.0,
        }[resource.resource_class]
    else:
        # En reconocimiento se premia agilidad (Tipo 3 y 4, Recurso Simple)
        type_weight = {4: 1.3, 3: 1.2, 2: 0.9, 1: 0.6}.get(resource.resource_type, 1.0)
        class_bonus = 8.0 if resource.resource_class == ResourceClass.RECURSO_SIMPLE else 0.0

    # 3. Penalización por ETA y bloqueos viales
    eta_penalty = 1.8 * route.eta_minutes
    block_penalty = 25.0 if route.status == RouteStatus.BLOQUEADA else (
        8.0 * route.penalty_factor if route.status == RouteStatus.DESVIO_POR_BLOQUEO else 0.0
    )

    utility = (
        (cluster_urgency * compatibility_bonus * type_weight)
        + class_bonus
        - eta_penalty
        - block_penalty
    )
    return round(utility, 2)


def _solve_linear_assignment_max(score_matrix: list[list[float]]) -> list[tuple[int, int]]:
    """
    Resuelve la asignación óptima 1-a-1 (programación lineal entera / matching bipartito de peso máximo)
    entre N recursos y M incidentes.
    Usa programación dinámica con máscara de bits cuando min(N, M) <= 14 (exacto) y
    búsqueda voraz con intercambio local (2-opt) para dimensiones mayores.
    """
    n_res = len(score_matrix)
    if n_res == 0:
        return []
    n_inc = len(score_matrix[0]) if score_matrix[0] else 0
    if n_inc == 0:
        return []

    # Si hay más recursos que incidentes o viceversa, hacemos DP sobre el lado más pequeño
    transpose = n_res > n_inc
    if transpose:
        matrix = [[score_matrix[r][c] for r in range(n_res)] for c in range(n_inc)]
    else:
        matrix = score_matrix

    rows = len(matrix)
    cols = len(matrix[0])

    if rows <= 14 and cols <= 20:
        memo: dict[tuple[int, int], tuple[float, list[tuple[int, int]]]] = {}

        def dp(r: int, used_mask: int) -> tuple[float, list[tuple[int, int]]]:
            if r == rows:
                return 0.0, []
            state = (r, used_mask)
            if state in memo:
                return memo[state]

            # Opción de no asignar esta fila
            best_val, best_pairs = dp(r + 1, used_mask)

            for c in range(cols):
                if not (used_mask & (1 << c)):
                    val = matrix[r][c]
                    if val <= -1e8:
                        continue
                    sub_val, sub_pairs = dp(r + 1, used_mask | (1 << c))
                    total = val + sub_val
                    if total > best_val:
                        best_val = total
                        best_pairs = [(r, c)] + sub_pairs

            memo[state] = (best_val, best_pairs)
            return memo[state]

        _, pairs = dp(0, 0)
        if transpose:
            return [(c, r) for r, c in pairs]
        return pairs

    # Fallback voraz global ordenado por mayor utilidad marginal + refinamiento 2-opt
    candidates: list[tuple[float, int, int]] = []
    for r in range(n_res):
        for c in range(n_inc):
            if score_matrix[r][c] > -1e8:
                candidates.append((score_matrix[r][c], r, c))
    candidates.sort(reverse=True)

    used_r: set[int] = set()
    used_c: set[int] = set()
    chosen: list[tuple[int, int]] = []
    for _, r, c in candidates:
        if r not in used_r and c not in used_c:
            used_r.add(r)
            used_c.add(c)
            chosen.append((r, c))
    return chosen


def optimize_assignments(
    resources: list[Resource],
    clusters: list[dict],
    road_blocks: list[RoadBlock] | None = None,
) -> list[AssignmentProposal]:
    """
    Algoritmo de asignación óptima N recursos <-> M incidentes:
    1. Filtra recursos DISPONIBLES e incidentes activos.
    2. Construye la matriz de utilidad U(r, c) considerando urgencia, compatibilidad SCI,
       regla de dos fases (RECONOCIMIENTO vs FUERZA_TAREA) y ruteo/ETA con bloqueos viales.
    3. Resuelve la asignación óptima global 1-a-1 para garantizar cobertura prioritaria.
    4. Si sobran recursos disponibles y hay incidentes FUERZA_TAREA de alta severidad (>= 7),
       asigna recursos de refuerzo hasta cubrir las necesidades del incidente.
    """
    available = [r for r in resources if r.status == ResourceStatus.DISPONIBLE]
    if not available or not clusters:
        return []

    routes: dict[tuple[int, int], RouteEstimate] = {}
    score_matrix: list[list[float]] = []

    for r_idx, res in enumerate(available):
        row_scores: list[float] = []
        for c_idx, cluster in enumerate(clusters):
            route = estimate_route(
                res.lat,
                res.lon,
                cluster["lat"],
                cluster["lon"],
                speed_kmh=res.speed_kmh,
                road_blocks=road_blocks,
            )
            routes[(r_idx, c_idx)] = route
            score = _pair_utility(
                res,
                cluster_urgency=float(cluster["urgency"]),
                cluster_recommendation=str(cluster["recommendation"]),
                cluster_kinds=list(cluster.get("kinds", [])),
                route=route,
            )
            row_scores.append(score)
        score_matrix.append(row_scores)

    primary_pairs = _solve_linear_assignment_max(score_matrix)
    proposals: list[AssignmentProposal] = []
    assigned_res_indices: set[int] = set()

    for r_idx, c_idx in primary_pairs:
        res = available[r_idx]
        cluster = clusters[c_idx]
        route = routes[(r_idx, c_idx)]
        score = score_matrix[r_idx][c_idx]
        assigned_res_indices.add(r_idx)
        proposals.append(
            AssignmentProposal(
                resource_id=res.id,
                resource_code=res.code,
                resource_class=res.resource_class.value,
                resource_type=res.resource_type,
                category=res.category.value,
                cluster_id=int(cluster["id"]),
                cluster_urgency=float(cluster["urgency"]),
                cluster_recommendation=str(cluster["recommendation"]),
                eta_minutes=route.eta_minutes,
                effective_distance_m=route.effective_distance_m,
                route_status=route.status.value,
                blocking_ids=route.blocking_ids,
                score=score,
            )
        )

    # Segunda pasada: refuerzo para clústeres verificados (FUERZA_TAREA) con severidad alta (>= 7)
    remaining_indices = [i for i in range(len(available)) if i not in assigned_res_indices]
    high_severity_clusters = [
        (c_idx, c)
        for c_idx, c in enumerate(clusters)
        if c.get("recommendation") == FUERZA_TAREA and int(c.get("severity", 0)) >= 7
    ]
    high_severity_clusters.sort(key=lambda item: float(item[1]["urgency"]), reverse=True)

    for c_idx, cluster in high_severity_clusters:
        if not remaining_indices:
            break
        best_r_idx = max(
            remaining_indices,
            key=lambda r_idx: score_matrix[r_idx][c_idx],
        )
        best_score = score_matrix[best_r_idx][c_idx]
        if best_score <= -1e8:
            continue
        remaining_indices.remove(best_r_idx)
        res = available[best_r_idx]
        route = routes[(best_r_idx, c_idx)]
        proposals.append(
            AssignmentProposal(
                resource_id=res.id,
                resource_code=res.code,
                resource_class=res.resource_class.value,
                resource_type=res.resource_type,
                category=res.category.value,
                cluster_id=int(cluster["id"]),
                cluster_urgency=float(cluster["urgency"]),
                cluster_recommendation=str(cluster["recommendation"]),
                eta_minutes=route.eta_minutes,
                effective_distance_m=route.effective_distance_m,
                route_status=route.status.value,
                blocking_ids=route.blocking_ids,
                score=best_score,
            )
        )

    proposals.sort(key=lambda p: (p.cluster_urgency, p.score), reverse=True)
    return proposals


class DispatchConsole:
    """
    Consola de despacho táctico SCI:
    - Inventario de recursos SCI-211 (clase, tipo 1-4, categoría, estado)
    - Gestión de bloqueos viales y cálculo de rutas/ETA
    - Asignación, reasignación y liberación de recursos
    - Ciclo de vida de incidentes (Pendiente -> En atención -> Resuelto / Falsa alarma con hora de cierre)
    - Bitácora inmutable de auditoría (quién / cuándo / qué)
    """

    def __init__(self) -> None:
        self._resources: dict[int, Resource] = {}
        self._road_blocks: dict[int, RoadBlock] = {}
        self._incidents: dict[int, IncidentRecord] = {}
        self._audit_log: list[DispatchAuditEntry] = []
        self._next_resource_id: int = 1
        self._next_block_id: int = 1
        self._next_audit_id: int = 1

    def reset(self) -> None:
        self._resources.clear()
        self._road_blocks.clear()
        self._incidents.clear()
        self._audit_log.clear()
        self._next_resource_id = 1
        self._next_block_id = 1
        self._next_audit_id = 1

    def _log(
        self,
        actor: str,
        action: str,
        resource_id: int | None,
        cluster_id: int | None,
        previous_state: str | None,
        new_state: str | None,
        details: str,
    ) -> DispatchAuditEntry:
        entry = DispatchAuditEntry(
            id=self._next_audit_id,
            timestamp=utc_now_iso(),
            actor=actor,
            action=action,
            resource_id=resource_id,
            cluster_id=cluster_id,
            previous_state=previous_state,
            new_state=new_state,
            details=details,
        )
        self._next_audit_id += 1
        self._audit_log.append(entry)
        return entry

    # --- Recursos SCI-211 ---

    def register_resource(
        self,
        code: str,
        name: str,
        resource_class: ResourceClass | str,
        resource_type: int,
        category: ResourceCategory | str,
        lat: float,
        lon: float,
        status: ResourceStatus | str = ResourceStatus.DISPONIBLE,
        speed_kmh: float = DEFAULT_SPEED_KMH,
        capacity: int = 4,
        leader: str | None = None,
        subordinates_count: int = 0,
        actor: str = "COMANDANTE_PC",
    ) -> Resource:
        r_class = ResourceClass(resource_class)
        r_cat = ResourceCategory(category)
        r_status = ResourceStatus(status)
        res = Resource(
            id=self._next_resource_id,
            code=code,
            name=name,
            resource_class=r_class,
            resource_type=resource_type,
            category=r_cat,
            status=r_status,
            lat=lat,
            lon=lon,
            speed_kmh=speed_kmh,
            capacity=capacity,
            leader=leader,
            subordinates_count=subordinates_count,
        )
        self._next_resource_id += 1
        self._resources[res.id] = res
        self._log(
            actor=actor,
            action="CHECKIN_RECURSO",
            resource_id=res.id,
            cluster_id=None,
            previous_state=None,
            new_state=res.status.value,
            details=f"Check-in SCI-211 {res.code} ({res.resource_class.value} Tipo {res.resource_type} - {res.category.value})",
        )
        return res

    def get_resource(self, resource_id: int) -> Resource:
        if resource_id not in self._resources:
            raise KeyError(f"Recurso {resource_id} no encontrado")
        return self._resources[resource_id]

    def list_resources(
        self,
        status: ResourceStatus | str | None = None,
        category: ResourceCategory | str | None = None,
        resource_class: ResourceClass | str | None = None,
        resource_type: int | None = None,
    ) -> list[Resource]:
        items = list(self._resources.values())
        if status is not None:
            st = ResourceStatus(status)
            items = [r for r in items if r.status == st]
        if category is not None:
            cat = ResourceCategory(category)
            items = [r for r in items if r.category == cat]
        if resource_class is not None:
            rc = ResourceClass(resource_class)
            items = [r for r in items if r.resource_class == rc]
        if resource_type is not None:
            items = [r for r in items if r.resource_type == resource_type]
        return sorted(items, key=lambda r: r.id)

    def update_resource(
        self,
        resource_id: int,
        status: ResourceStatus | str | None = None,
        lat: float | None = None,
        lon: float | None = None,
        actor: str = "COMANDANTE_PC",
        reason: str = "",
    ) -> Resource:
        res = self.get_resource(resource_id)
        prev_status = res.status.value
        if lat is not None:
            res.lat = lat
        if lon is not None:
            res.lon = lon
        if status is not None:
            new_st = ResourceStatus(status)
            if new_st != ResourceStatus.ASIGNADO and res.assigned_cluster_id is not None:
                old_cluster = res.assigned_cluster_id
                inc = self._incidents.get(old_cluster)
                if inc and res.id in inc.assigned_resource_ids:
                    inc.assigned_resource_ids.remove(res.id)
                    inc.updated_at = utc_now_iso()
                res.assigned_cluster_id = None
            res.status = new_st
            self._log(
                actor=actor,
                action="ACTUALIZAR_RECURSO",
                resource_id=res.id,
                cluster_id=res.assigned_cluster_id,
                previous_state=prev_status,
                new_state=res.status.value,
                details=reason or f"Actualización de estado de {res.code}",
            )
        return res

    # --- Bloqueos Viales ---

    def add_road_block(
        self,
        lat: float,
        lon: float,
        radius_m: float = 60.0,
        severity: int = 8,
        description: str = "",
        actor: str = "COMANDANTE_PC",
    ) -> RoadBlock:
        if not (1 <= severity <= 10):
            raise ValueError("severity del bloqueo vial debe estar entre 1 y 10")
        if radius_m <= 0:
            raise ValueError("radius_m debe ser mayor a 0")
        block = RoadBlock(
            id=self._next_block_id,
            lat=lat,
            lon=lon,
            radius_m=radius_m,
            severity=severity,
            description=description,
            active=True,
        )
        self._next_block_id += 1
        self._road_blocks[block.id] = block
        self._log(
            actor=actor,
            action="REGISTRO_BLOQUEO_VIAL",
            resource_id=None,
            cluster_id=None,
            previous_state=None,
            new_state="ACTIVO",
            details=f"Bloqueo vial #{block.id} en ({lat:.5f}, {lon:.5f}) r={radius_m}m sev={severity}: {description}",
        )
        return block

    def list_road_blocks(self, active_only: bool = True) -> list[RoadBlock]:
        blocks = list(self._road_blocks.values())
        if active_only:
            blocks = [b for b in blocks if b.active]
        return sorted(blocks, key=lambda b: b.id)

    def remove_road_block(
        self,
        block_id: int,
        actor: str = "COMANDANTE_PC",
        reason: str = "Vía despejada",
    ) -> RoadBlock:
        if block_id not in self._road_blocks:
            raise KeyError(f"Bloqueo vial {block_id} no encontrado")
        block = self._road_blocks[block_id]
        prev = "ACTIVO" if block.active else "INACTIVO"
        block.active = False
        self._log(
            actor=actor,
            action="LIBERACION_BLOQUEO_VIAL",
            resource_id=None,
            cluster_id=None,
            previous_state=prev,
            new_state="INACTIVO",
            details=f"Bloqueo #{block.id} liberado: {reason}",
        )
        return block

    # --- Ciclo de Vida de Incidentes ---

    def get_or_create_incident(self, cluster_id: int) -> IncidentRecord:
        if cluster_id not in self._incidents:
            self._incidents[cluster_id] = IncidentRecord(cluster_id=cluster_id)
        return self._incidents[cluster_id]

    def list_incidents(
        self, status: IncidentLifecycleStatus | str | None = None
    ) -> list[IncidentRecord]:
        items = list(self._incidents.values())
        if status is not None:
            st = IncidentLifecycleStatus(status)
            items = [i for i in items if i.status == st]
        return sorted(items, key=lambda i: i.cluster_id)

    def update_incident_status(
        self,
        cluster_id: int,
        new_status: IncidentLifecycleStatus | str,
        actor: str = "COMANDANTE_PC",
        notes: str = "",
    ) -> IncidentRecord:
        inc = self.get_or_create_incident(cluster_id)
        target_status = IncidentLifecycleStatus(new_status)
        prev_status = inc.status.value
        now = utc_now_iso()

        inc.status = target_status
        inc.updated_at = now
        if notes:
            inc.notes = notes
        inc.commander = actor

        if target_status in {
            IncidentLifecycleStatus.RESUELTO,
            IncidentLifecycleStatus.FALSA_ALARMA,
        }:
            inc.closed_at = now
            # Al cerrar el incidente se liberan automáticamente los recursos asignados
            released_codes: list[str] = []
            for res_id in list(inc.assigned_resource_ids):
                res = self._resources.get(res_id)
                if res:
                    res.status = ResourceStatus.DISPONIBLE
                    res.assigned_cluster_id = None
                    released_codes.append(res.code)
            inc.assigned_resource_ids.clear()
            extra = (
                f" | Recursos liberados: {', '.join(released_codes)}"
                if released_codes
                else ""
            )
        else:
            inc.closed_at = None
            extra = ""

        self._log(
            actor=actor,
            action="CAMBIO_ESTADO_INCIDENTE",
            resource_id=None,
            cluster_id=cluster_id,
            previous_state=prev_status,
            new_state=target_status.value,
            details=f"Incidente #{cluster_id} -> {target_status.value}. {notes}{extra}".strip(),
        )
        return inc

    # --- Operaciones de Consola de Despacho ---

    def assign_resource(
        self,
        resource_id: int,
        cluster_id: int,
        actor: str = "COMANDANTE_PC",
        reason: str = "",
        cluster_lat: float | None = None,
        cluster_lon: float | None = None,
    ) -> dict:
        res = self.get_resource(resource_id)
        if res.status != ResourceStatus.DISPONIBLE:
            raise ValueError(
                f"El recurso {res.code} no está DISPONIBLE (estado actual: {res.status.value})"
            )

        inc = self.get_or_create_incident(cluster_id)
        if inc.status in {
            IncidentLifecycleStatus.RESUELTO,
            IncidentLifecycleStatus.FALSA_ALARMA,
        }:
            raise ValueError(
                f"No se puede despachar al incidente #{cluster_id} porque está cerrado ({inc.status.value})"
            )

        prev_res_status = res.status.value
        prev_inc_status = inc.status.value

        res.status = ResourceStatus.ASIGNADO
        res.assigned_cluster_id = cluster_id

        if res.id not in inc.assigned_resource_ids:
            inc.assigned_resource_ids.append(res.id)
        if inc.status == IncidentLifecycleStatus.PENDIENTE:
            inc.status = IncidentLifecycleStatus.EN_ATENCION
            self._log(
                actor=actor,
                action="CAMBIO_ESTADO_INCIDENTE",
                resource_id=res.id,
                cluster_id=cluster_id,
                previous_state=prev_inc_status,
                new_state=inc.status.value,
                details=f"Incidente #{cluster_id} pasa a EN_ATENCION al despachar {res.code}",
            )
        inc.updated_at = utc_now_iso()

        route_info = None
        eta_text = ""
        if cluster_lat is not None and cluster_lon is not None:
            route = estimate_route(
                res.lat,
                res.lon,
                cluster_lat,
                cluster_lon,
                speed_kmh=res.speed_kmh,
                road_blocks=self.list_road_blocks(active_only=True),
            )
            route_info = route
            eta_text = f" (ETA {route.eta_minutes} min, ruta {route.status.value})"

        audit = self._log(
            actor=actor,
            action="ASIGNAR_RECURSO",
            resource_id=res.id,
            cluster_id=cluster_id,
            previous_state=prev_res_status,
            new_state=res.status.value,
            details=f"Asignado {res.code} a incidente #{cluster_id}{eta_text}. {reason}".strip(),
        )
        return {
            "resource": res,
            "incident": inc,
            "route": route_info,
            "audit": audit,
        }

    def reassign_resource(
        self,
        resource_id: int,
        target_cluster_id: int,
        actor: str = "COMANDANTE_PC",
        reason: str = "",
        target_lat: float | None = None,
        target_lon: float | None = None,
    ) -> dict:
        res = self.get_resource(resource_id)
        if res.status != ResourceStatus.ASIGNADO or res.assigned_cluster_id is None:
            raise ValueError(
                f"El recurso {res.code} debe estar ASIGNADO para poder reasignarse"
            )
        old_cluster_id = res.assigned_cluster_id
        if old_cluster_id == target_cluster_id:
            raise ValueError(
                f"El recurso {res.code} ya está asignado al incidente #{target_cluster_id}"
            )

        target_inc = self.get_or_create_incident(target_cluster_id)
        if target_inc.status in {
            IncidentLifecycleStatus.RESUELTO,
            IncidentLifecycleStatus.FALSA_ALARMA,
        }:
            raise ValueError(
                f"El incidente destino #{target_cluster_id} está cerrado ({target_inc.status.value})"
            )

        old_inc = self.get_or_create_incident(old_cluster_id)
        if res.id in old_inc.assigned_resource_ids:
            old_inc.assigned_resource_ids.remove(res.id)
            old_inc.updated_at = utc_now_iso()
            if (
                not old_inc.assigned_resource_ids
                and old_inc.status == IncidentLifecycleStatus.EN_ATENCION
            ):
                old_inc.status = IncidentLifecycleStatus.PENDIENTE

        res.assigned_cluster_id = target_cluster_id
        if res.id not in target_inc.assigned_resource_ids:
            target_inc.assigned_resource_ids.append(res.id)
        if target_inc.status == IncidentLifecycleStatus.PENDIENTE:
            target_inc.status = IncidentLifecycleStatus.EN_ATENCION
        target_inc.updated_at = utc_now_iso()

        route_info = None
        eta_text = ""
        if target_lat is not None and target_lon is not None:
            route = estimate_route(
                res.lat,
                res.lon,
                target_lat,
                target_lon,
                speed_kmh=res.speed_kmh,
                road_blocks=self.list_road_blocks(active_only=True),
            )
            route_info = route
            eta_text = f" (ETA {route.eta_minutes} min, ruta {route.status.value})"

        audit = self._log(
            actor=actor,
            action="REASIGNAR_RECURSO",
            resource_id=res.id,
            cluster_id=target_cluster_id,
            previous_state=f"ASIGNADO:{old_cluster_id}",
            new_state=f"ASIGNADO:{target_cluster_id}",
            details=f"Reasignado {res.code} de incidente #{old_cluster_id} a #{target_cluster_id}{eta_text}. {reason}".strip(),
        )
        return {
            "resource": res,
            "previous_cluster_id": old_cluster_id,
            "incident": target_inc,
            "route": route_info,
            "audit": audit,
        }

    def release_resource(
        self,
        resource_id: int,
        actor: str = "COMANDANTE_PC",
        reason: str = "Misión completada",
    ) -> dict:
        res = self.get_resource(resource_id)
        if res.status != ResourceStatus.ASIGNADO:
            raise ValueError(f"El recurso {res.code} no está ASIGNADO")

        old_cluster_id = res.assigned_cluster_id
        if old_cluster_id is not None and old_cluster_id in self._incidents:
            inc = self._incidents[old_cluster_id]
            if res.id in inc.assigned_resource_ids:
                inc.assigned_resource_ids.remove(res.id)
                inc.updated_at = utc_now_iso()

        res.status = ResourceStatus.DISPONIBLE
        res.assigned_cluster_id = None

        audit = self._log(
            actor=actor,
            action="LIBERAR_RECURSO",
            resource_id=res.id,
            cluster_id=old_cluster_id,
            previous_state="ASIGNADO",
            new_state=ResourceStatus.DISPONIBLE.value,
            details=f"Recurso {res.code} liberado del incidente #{old_cluster_id}. {reason}".strip(),
        )
        return {
            "resource": res,
            "released_from_cluster_id": old_cluster_id,
            "audit": audit,
        }

    def optimize_and_dispatch(
        self,
        clusters: list[dict],
        apply: bool = False,
        actor: str = "MOTOR_ALGORITMICO",
    ) -> list[AssignmentProposal]:
        active_clusters: list[dict] = []
        for c in clusters:
            cid = int(c["id"])
            inc = self.get_or_create_incident(cid)
            if inc.status not in {
                IncidentLifecycleStatus.RESUELTO,
                IncidentLifecycleStatus.FALSA_ALARMA,
            }:
                active_clusters.append(c)

        proposals = optimize_assignments(
            resources=self.list_resources(status=ResourceStatus.DISPONIBLE),
            clusters=active_clusters,
            road_blocks=self.list_road_blocks(active_only=True),
        )

        if apply:
            cluster_map = {int(c["id"]): c for c in active_clusters}
            for prop in proposals:
                c_data = cluster_map.get(prop.cluster_id, {})
                self.assign_resource(
                    resource_id=prop.resource_id,
                    cluster_id=prop.cluster_id,
                    actor=actor,
                    reason=f"Optimización algorítmica SCI (score={prop.score})",
                    cluster_lat=c_data.get("lat"),
                    cluster_lon=c_data.get("lon"),
                )
        return proposals

    def list_audit_log(
        self,
        cluster_id: int | None = None,
        resource_id: int | None = None,
        actor: str | None = None,
        action: str | None = None,
    ) -> list[DispatchAuditEntry]:
        entries = list(self._audit_log)
        if cluster_id is not None:
            entries = [e for e in entries if e.cluster_id == cluster_id]
        if resource_id is not None:
            entries = [e for e in entries if e.resource_id == resource_id]
        if actor is not None:
            entries = [e for e in entries if e.actor == actor]
        if action is not None:
            entries = [e for e in entries if e.action == action]
        return entries


dispatch_console = DispatchConsole()
