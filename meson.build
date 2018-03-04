project('D-YAML', 'd',
    meson_version: '>=0.40.0',
    subproject_dir: 'contrib'
)

project_version      = '0.6.2'
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
    'source/dyaml/fastcharsearch.d',
    'source/dyaml/flags.d',
    'source/dyaml/hacks.d',
    'source/dyaml/linebreak.d',
    'source/dyaml/loader.d',
    'source/dyaml/node.d',
    'source/dyaml/nogcutil.d',
    'source/dyaml/package.d',
    'source/dyaml/parser.d',
    'source/dyaml/queue.d',
    'source/dyaml/reader.d',
    'source/dyaml/representer.d',
    'source/dyaml/resolver.d',
    'source/dyaml/scanner.d',
    'source/dyaml/serializer.d',
    'source/dyaml/stream.d',
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
    'source/dyaml/token.d',
    'source/dyaml/unused.d'
]
install_subdir('source/dyaml', install_dir: 'include/d/yaml/')

tinyendian_dep = dependency('tinyendian', version: '>=0.1.2', required: false)
if not tinyendian_dep.found()
    tinyendian_sp = subproject('tinyendian')
    tinyendian_dep = declare_dependency(link_with: tinyendian_sp.get_variable('tinyendian_lib'),
        include_directories: tinyendian_sp.get_variable('src_dir')
    )
endif

dyaml_lib = library('dyaml',
        [dyaml_src],
        include_directories: [src_dir],
        dependencies: [tinyendian_dep],
        install: true,
        version: project_version,
        soversion: project_soversion
)
pkgc.generate(name: 'dyaml',
              libraries: dyaml_lib,
              subdirs: 'd/yaml/',
              version: project_version,
              description: 'YAML parser and emitter for the D programming language.'
)

# Make D-YAML easy to use as subproject
dyaml_dep = declare_dependency(
    link_with: dyaml_lib,
    include_directories: [src_dir],
    dependencies: [tinyendian_dep]
)
