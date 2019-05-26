project('D-YAML', 'd',
    meson_version: '>=0.40.0',
    subproject_dir: 'contrib',
    version: '0.8.0'
)

project_soversion    = '0'

src_dir = include_directories('source/')
pkgc = import('pkgconfig')

dyaml_src = [
    'source/dyaml/composer.d',
    'source/dyaml/constructor.d',
    'source/dyaml/dumper.d',
    'source/dyaml/emitter.d',
    'source/dyaml/encoding.d',
    'source/dyaml/escapes.d',
    'source/dyaml/event.d',
    'source/dyaml/exception.d',
    'source/dyaml/linebreak.d',
    'source/dyaml/loader.d',
    'source/dyaml/node.d',
    'source/dyaml/package.d',
    'source/dyaml/parser.d',
    'source/dyaml/queue.d',
    'source/dyaml/reader.d',
    'source/dyaml/representer.d',
    'source/dyaml/resolver.d',
    'source/dyaml/scanner.d',
    'source/dyaml/serializer.d',
    'source/dyaml/style.d',
    'source/dyaml/tagdirective.d',
    'source/dyaml/test/common.d',
    'source/dyaml/test/compare.d',
    'source/dyaml/test/constructor.d',
    'source/dyaml/test/emitter.d',
    'source/dyaml/test/errors.d',
    'source/dyaml/test/inputoutput.d',
    'source/dyaml/test/reader.d',
    'source/dyaml/test/representer.d',
    'source/dyaml/test/resolver.d',
    'source/dyaml/test/tokens.d',
    'source/dyaml/token.d'
]
install_subdir('source/dyaml', install_dir: 'include/d/yaml/')

tinyendian_dep = dependency('tinyendian', version: '>=0.2.0', fallback: ['tinyendian', 'tinyendian_dep'])

dyaml_lib = library('dyaml',
        [dyaml_src],
        include_directories: [src_dir],
        dependencies: [tinyendian_dep],
        install: true,
        version: meson.project_version(),
        soversion: project_soversion
)
pkgc.generate(name: 'dyaml',
              libraries: dyaml_lib,
              subdirs: 'd/yaml/',
              version: meson.project_version(),
              description: 'YAML parser and emitter for the D programming language.'
)

# Make D-YAML easy to use as subproject
dyaml_dep = declare_dependency(
    link_with: dyaml_lib,
    include_directories: [src_dir],
    dependencies: [tinyendian_dep]
)
