-- Parque Solar Valle Aurora · Datos de demostración FICTICIOS (fechas relativas al día en que se cargan)

with cr as (
  insert into public.contratos (nombre, tipo, contraparte, fecha_firma, resumen)
  values ('Crédito Simple – Planta Solar Demo', 'Crédito', 'Banco de Desarrollo Demo',
          public.hoy_mx() - 400,
          'Préstamo de largo plazo a Energía Solar Demo, S.A.P.I. de C.V. para construir y operar una planta solar. DATOS FICTICIOS para demostración.')
  returning id
)
insert into public.obligaciones (contrato_id, titulo, explicacion_simple, clausula, categoria, periodicidad, proxima_fecha, dias_aviso, responsable, consecuencia, prioridad)
select cr.id, v.* from cr, (values
 ('Pagar intereses y amortización trimestral',
  'Cada tres meses hay que pagarle al banco los intereses y la parte del préstamo que toca.',
  'Cláusula 6.1', 'Pagar', 'Trimestral', public.hoy_mx() + 12, '{30,15,7,1}'::int[], 'Tesorería',
  'Se cobran intereses moratorios y el banco puede exigir el pago anticipado de todo el crédito.', 'Alta'),
 ('Entregar estados financieros trimestrales',
  'Mandar al banco los números de la empresa (balance y resultados) de cada trimestre, a más tardar 45 días después de que termine.',
  'Cláusula 9.1 (a)', 'Reportar', 'Trimestral', public.hoy_mx() - 4, '{15,7,1}'::int[], 'Finanzas',
  'Es un incumplimiento de información; si no se corrige en el plazo de cura puede volverse causa de vencimiento anticipado.', 'Alta'),
 ('Entregar estados financieros anuales auditados',
  'Una vez al año, entregar los números de la empresa revisados por un auditor externo.',
  'Cláusula 9.1 (b)', 'Reportar', 'Anual', public.hoy_mx() + 58, '{30,15,7,1}'::int[], 'Finanzas',
  'Incumplimiento de información; el banco puede retener desembolsos o distribuciones.', 'Media'),
 ('Certificar la razón de cobertura de deuda (mínimo 1.20x)',
  'Demostrar al banco que el dinero que genera el proyecto alcanza con holgura para pagar la deuda: por cada $1 de deuda debe haber al menos $1.20 de flujo.',
  'Cláusula 9.2', 'Reportar', 'Semestral', public.hoy_mx() + 6, '{30,15,7,1}'::int[], 'Finanzas',
  'Si la razón queda por debajo del mínimo, se bloquean los dividendos y puede ser causa de incumplimiento.', 'Alta'),
 ('Renovar los seguros y nombrar al banco como beneficiario',
  'Tener asegurada la planta todo el tiempo y que el banco aparezca como beneficiario preferente en las pólizas.',
  'Cláusula 10.3', 'Mantener', 'Anual', public.hoy_mx() + 21, '{45,30,15,7,1}'::int[], 'Jurídico / Seguros',
  'Si la planta se queda sin seguro, el banco puede contratarlo con cargo a la empresa y declarar un incumplimiento.', 'Alta'),
 ('Revisar que los permisos de operación sigan vigentes',
  'Confirmar que la planta tiene todos sus permisos (energía, ambientales, municipales) vigentes y sin observaciones.',
  'Cláusula 10.5', 'Mantener', 'Semestral', public.hoy_mx() + 40, '{30,15,7}'::int[], 'Jurídico',
  'Perder un permiso es causa de vencimiento anticipado y puede detener la operación.', 'Alta'),
 ('Mantener fondeada la cuenta de reserva',
  'Tener guardado en una cuenta especial el equivalente a 6 meses de pagos al banco, por si algún mes no alcanza el dinero.',
  'Cláusula 7.4', 'Mantener', 'Trimestral', public.hoy_mx() + 45, '{30,15,7}'::int[], 'Tesorería',
  'El faltante debe reponerse; mientras tanto no se pueden repartir dividendos.', 'Media'),
 ('Enviar reporte mensual de operación',
  'Mandar al banco un resumen de cuánta energía produjo la planta, cuánto se vendió y si hubo fallas.',
  'Cláusula 9.3', 'Reportar', 'Mensual', public.hoy_mx() + 2, '{7,3,1}'::int[], 'Operaciones',
  'Incumplimiento de información.', 'Media'),
 ('Avisar al banco de demandas, multas o eventos importantes',
  'Si pasa algo grave (una demanda, una multa, un accidente, la pérdida de un cliente), avisarle al banco dentro de 5 días hábiles.',
  'Cláusula 9.4', 'Notificar', 'Por evento', null, '{30,15,7,1}'::int[], 'Jurídico',
  'No avisar a tiempo es un incumplimiento por sí mismo, aunque el evento se resuelva.', 'Alta'),
 ('No repartir dividendos si no se cumple la razón de cobertura',
  'La empresa no puede pagar utilidades a sus socios mientras no cumpla con la razón mínima de cobertura y esté al corriente con el banco.',
  'Cláusula 11.2', 'No hacer', 'Continua', null, '{30,15,7,1}'::int[], 'Dirección / Consejo',
  'Repartir dividendos en contra de esta regla es causa de vencimiento anticipado.', 'Alta'),
 ('Entregar opinión legal para el primer desembolso',
  'Antes de recibir el dinero, entregar al banco una opinión de abogados que confirme que la empresa y sus contratos son válidos.',
  'Cláusula 4.1 (c)', 'Hacer', 'Única', null, '{30,15,7,1}'::int[], 'Jurídico',
  'Sin este documento el banco no entrega el dinero.', 'Media')
) as v(titulo, explicacion_simple, clausula, categoria, periodicidad, proxima_fecha, dias_aviso, responsable, consecuencia, prioridad);

with fi as (
  insert into public.contratos (nombre, tipo, contraparte, fecha_firma, resumen)
  values ('Fideicomiso de Garantía y Fuente de Pago F/1000', 'Fideicomiso', 'Banco Fiduciario Demo',
          public.hoy_mx() - 395,
          'Fideicomiso donde se concentran los ingresos de la planta y desde el cual se paga al banco. DATOS FICTICIOS para demostración.')
  returning id
)
insert into public.obligaciones (contrato_id, titulo, explicacion_simple, clausula, categoria, periodicidad, proxima_fecha, dias_aviso, responsable, consecuencia, prioridad)
select fi.id, v.* from fi, (values
 ('Depositar todos los ingresos en la cuenta del fideicomiso',
  'Todo el dinero que paguen los clientes de la planta debe entrar a la cuenta del fideicomiso, nunca a otra cuenta de la empresa.',
  'Cláusula 5', 'Hacer', 'Continua', null::date, '{30,15,7,1}'::int[], 'Tesorería',
  'Desviar ingresos es un incumplimiento grave del fideicomiso y del crédito.', 'Alta'),
 ('Enviar la instrucción mensual de pagos al fiduciario',
  'Cada mes, decirle al banco fiduciario en qué orden y a quién pagar con el dinero del fideicomiso (la "cascada").',
  'Cláusula 8.2', 'Hacer', 'Mensual', public.hoy_mx() + 5, '{7,3,1}'::int[], 'Tesorería',
  'Sin instrucción, el fiduciario no paga y pueden atrasarse los pagos al banco y a proveedores.', 'Alta'),
 ('Pagar los honorarios anuales del fiduciario',
  'Pagar una vez al año la cuota del banco que administra el fideicomiso.',
  'Cláusula 14', 'Pagar', 'Anual', public.hoy_mx() + 16, '{30,15,7,1}'::int[], 'Tesorería',
  'El fiduciario puede cobrar intereses o descontarlo del patrimonio del fideicomiso.', 'Media'),
 ('Actualizar el expediente de identificación (KYC)',
  'Una vez al año, entregar al fiduciario los documentos actualizados de la empresa y sus representantes (actas, poderes, identificaciones).',
  'Cláusula 17', 'Hacer', 'Anual', public.hoy_mx() - 10, '{30,15,7,1}'::int[], 'Jurídico',
  'El fiduciario puede suspender operaciones del fideicomiso hasta que se actualice.', 'Media'),
 ('Celebrar la sesión trimestral del Comité Técnico',
  'Reunir cada tres meses al comité que supervisa el fideicomiso y dejar constancia en un acta firmada.',
  'Cláusula 12', 'Hacer', 'Trimestral', public.hoy_mx() + 33, '{15,7,1}'::int[], 'Jurídico',
  'Las decisiones pendientes del fideicomiso no pueden tomarse.', 'Baja'),
 ('Notificar a los clientes que paguen a la cuenta del fideicomiso',
  'Avisar por escrito a cada cliente que, a partir de ahora, debe pagar en la cuenta del fideicomiso.',
  'Cláusula 6.3', 'Notificar', 'Única', null::date, '{30,15,7,1}'::int[], 'Jurídico',
  'Si los clientes pagan a otra cuenta, el fideicomiso no recibe el dinero que garantiza el crédito.', 'Alta')
) as v(titulo, explicacion_simple, clausula, categoria, periodicidad, proxima_fecha, dias_aviso, responsable, consecuencia, prioridad);

insert into public.cumplimientos (obligacion_id, periodo_fecha, fecha_cumplimiento, nota, registrado_por)
select id, null, public.hoy_mx() - 380, 'Opinión legal entregada antes del primer desembolso.', 'Jurídico'
from public.obligaciones where titulo = 'Entregar opinión legal para el primer desembolso';
insert into public.cumplimientos (obligacion_id, periodo_fecha, fecha_cumplimiento, nota, registrado_por)
select id, null, public.hoy_mx() - 370, 'Notificaciones entregadas a los 4 clientes con acuse.', 'Jurídico'
from public.obligaciones where titulo = 'Notificar a los clientes que paguen a la cuenta del fideicomiso';
insert into public.cumplimientos (obligacion_id, periodo_fecha, fecha_cumplimiento, nota, registrado_por)
select id, (proxima_fecha - interval '3 months')::date, (proxima_fecha - interval '3 months')::date - 1, 'Pago realizado un día antes.', 'Tesorería'
from public.obligaciones where titulo = 'Pagar intereses y amortización trimestral';
insert into public.cumplimientos (obligacion_id, periodo_fecha, fecha_cumplimiento, nota, registrado_por)
select id, (proxima_fecha - interval '1 month')::date, (proxima_fecha - interval '1 month')::date - 2, 'Instrucción enviada por correo al fiduciario.', 'Tesorería'
from public.obligaciones where titulo = 'Enviar la instrucción mensual de pagos al fiduciario';

select public.generar_alertas();
