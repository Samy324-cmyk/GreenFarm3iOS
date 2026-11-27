"""Regional vocabulary applied after all stable language references are resolved."""
import re
from .media import read_groups, write_groups


TERMS = {
    'pienso': 'alimento', 'piensos':'alimentos',
    'bote de miel':'frasco de miel', 'botes de miel':'frascos de miel',
    'tortitas de miel':'hot cakes de miel', 'magdalena de miel':'mantecada de miel',
    'patatas de miel':'papas con miel', 'paneles adicionales':'panales adicionales',
    'albaricoquero':'árbol de chabacano', 'albaricoque':'chabacano',
    'melocotonero':'duraznero', 'melocotoneros':'durazneros',
    'melocotón':'durazno', 'melocotones':'duraznos',
    'banano':'plátano', 'bananos':'plátanos',
    'enhorabuena':'felicidades', 'coger tu recompensa':'recoger tu recompensa',
    'coge tus recompensas':'recoge tus recompensas',
    'las tartas':'los pasteles', 'unas cuantas tartas':'unos cuantos pasteles',
    'tartas están deliciosas':'pasteles están deliciosos', 'tartas':'pasteles',
}
PATTERN = re.compile(r'\b('+ '|'.join(map(re.escape, sorted(TERMS, key=len, reverse=True)))+r')\b', re.IGNORECASE)


def adapt(text):
    def replace(match):
        original = match[0]
        # This line is about a character declining to go to the moon.
        if original.lower() == 'pienso' and text[match.end():].startswith(' ir'):
            return original
        value = TERMS[original.lower()]
        if original.isupper():
            return value.upper()
        return value[:1].upper()+value[1:] if original[0].isupper() else value
    return PATTERN.sub(replace, text).replace('¡Y ahora a por la diversión!', '¡Y ahora viene lo divertido!')


def regionalize(binary):
    groups = read_groups(binary)
    changes = 0
    for group in groups.values():
        for i, text in enumerate(group):
            translated = adapt(text)
            if translated != text:
                if re.findall(r'%[\w%]*',text) != re.findall(r'%[\w%]*',translated):
                    raise ValueError('Localization changed a format token')
                changes += 1
                group[i] = translated
    return write_groups(groups), changes
