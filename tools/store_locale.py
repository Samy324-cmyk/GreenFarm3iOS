"""Translate the two independent legacy storefront text resources to es-MX."""
from itertools import accumulate
import struct


CATALOG = (
    'CATÁLOGO COMPLETO', '¡OPRIME 5 PARA VISITAR!', '¡OPRIME 5\nPARA OBTENERLO!',
    '¡OPRIME OK PARA VISITAR!', '¡OPRIME OK\nPARA OBTENERLO!', 'ELEGIR', 'ATRÁS',
    '¡TOCA AQUÍ PARA VISITAR!', '¡TOCA AQUÍ\nPARA OBTENERLO!',
    '¡OPRIME OK EN LA CRUCETA PARA VISITAR!', '¡OPRIME OK EN LA CRUCETA PARA OBTENERLO!',
    'EXPLORA LOS MEJORES JUEGOS DE GAMELOFT', 'CLUB GAMELOFT', 'MÁS JUEGOS DE GAMELOFT',
    'OPRIME 5 PARA VER\nEL CATÁLOGO COMPLETO', 'OPRIME OK PARA VER\nEL CATÁLOGO COMPLETO',
    'JUEGOS', 'OFERTAS ESPECIALES', 'MÁS JUEGOS', '¡OBTENLO AHORA!',
    'PUEDEN APLICARSE CARGOS POR DATOS', 'VAS A SALIR DEL JUEGO.\n¿QUIERES CONTINUAR?', 'CARGANDO',
)


def catalog_text(data):
    count, start, offset, stop = struct.unpack_from('<H3I',data)
    if (count,start,stop) != (3,0,len(data)-14):
        raise ValueError('Invalid catalog header')
    block = data[14+offset:]
    length, text_size = struct.unpack_from('<2H',block)
    index_size, n = struct.unpack_from('<2H',block,4+text_size)
    if (length != len(block)-2 or index_size != 2+2*n or n!=27
            or 8+text_size+2*n != len(block)):
        raise ValueError('Invalid catalog string block')
    ends = struct.unpack_from(f'<{n}H',block,8+text_size)
    if ends[-1]!=text_size or list(ends)!=sorted(ends):
        raise ValueError('Invalid string offsets')
    words = [block[4+a:4+b].decode('utf-8') for a,b in zip((0,*ends),ends)]
    return data[14:14+offset],words


def localize_store(jar):
    metadata, old = catalog_text(jar.read('dataIGP'))
    if old[4]!='COMPLETE CATALOGUE' or old[-1]!='LOADING':
        raise ValueError('Unknown legacy catalog')
    words = [*old[:4],*CATALOG]
    encoded = [s.encode('utf-8') for s in words]
    text = b''.join(encoded)
    ends = list(accumulate(map(len,encoded)))
    index = struct.pack('<H',len(ends))+struct.pack(f'<{len(ends)}H',*ends)
    body = struct.pack('<H',len(text))+text+struct.pack('<H',len(index))+index
    packet = struct.pack('<H',len(body))+body
    catalog = struct.pack('<H3I',3,0,len(metadata),len(metadata)+len(packet))+metadata+packet
    if catalog_text(catalog)!=(metadata,words):
        raise ValueError('Translated catalog cannot be read back')

    source = jar.read('IAP_texts').decode('utf-8').splitlines()
    records = [s.split(';',1) for s in source if s]
    if [int(k) for k,_ in records]!=[2,14,16,22,24,30,32,42,56,59,61]:
        raise ValueError('Unknown regional notice set')
    lines = []
    for key,original in records:
        if any(token not in original for token in ('gameloft.com/conditions','support@gameloft.com','<support_number>')):
            raise ValueError('Missing contact details in regional notice')
        intro = ('Puedes jugar gratis y, si quieres, comprar artículos del juego con dinero real. '
                 'Las compras se cobran a tu cuenta de celular. Pide permiso a la persona que paga la cuenta. '
                 'El precio depende del artículo y de tu compañía celular. ')
        rate = 'Según tu plan, pueden aplicarse cargos por mensajes y uso de datos. '
        if key in ('14','16','22','24','30'):
            rate += 'Los cargos se suman a tu factura o se descuentan de tu saldo de prepago. '
        elif key in ('32','42'):
            rate = 'Según tu plan, pueden aplicarse cargos por uso de datos. '
        elif key=='56':
            rate = 'Cada SMS enviado cuesta Rs 3/-, además de los cargos por datos. '
        terms = (intro+rate+'Los artículos de un solo uso que compres en el juego solo se pueden descargar una vez. '
                 'No se pueden transferir entre dispositivos ni reponer después de descargarlos. '
                 'Este servicio no es una suscripción. Consulta los términos y condiciones completos en gameloft.com/conditions. '
                 'Si necesitas ayuda, escribe a support@gameloft.com<phone> o llama al <support_number></phone>.')
        if key=='61':
            terms += (' Línea de atención al cliente 6338 7005. Proveedor de SMS premium Macro Kiosk Pte Limited. '
                      'Horario de lunes a viernes, de 9:00 a 18:00.')
        lines.append(key+';'+terms)
    return {'dataIGP':catalog, 'IAP_texts':('\n'.join(lines)+'\n\n').encode('utf-8')}
