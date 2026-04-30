var   gulp                         = require('gulp');
var   fs                           = require('fs');
var   sass                         = require('gulp-sass');
var   replace                      = require('gulp-replace');
var   rename                       = require('gulp-rename');
var   showdown                     = require('showdown');

var   converter                    = new showdown.Converter();
converter.setOption('strikethrough', true);
converter.setOption('tables', true);
converter.setOption('parseImgDimensions', true);
converter.setOption('ghCodeBlocks', true);
converter.setOption('tasklists', true);
converter.setFlavor('github');
var   server                       = require('gulp-server-livereload');
var   registered_top_pages         = [];
var   registered_watchers          = [];
var   registered_link_replacements = [];
var   registered_blog_entries      = {};
var   registered_translation_entries      = {};
var   registered_development_entries      = {};

var     Mutex = require('async-mutex').Mutex;
const entriesFolder                = 'entries/';
const buildFolder                  = 'docs';
const fsExtra                      = require('fs-extra');
const blogMutex = new Mutex();
const translationMutex = new Mutex();
const developmentMutex = new Mutex();

// fsExtra.removeSync(buildFolder);
fsExtra.ensureDirSync(buildFolder);

var scan_directory = function (folder, root) {
    let files = fs.readdirSync(folder);
    files.forEach(file => {
        let fullPath         = `${folder}`;
        let relativePath     = `${fullPath}`.replace(`${root}`, '');
        let filename         = `${file}`;
        let fileAbsolutePath = `${folder}${file}`;
        if (fs.statSync(fileAbsolutePath).isDirectory()){
            scan_directory(`${fileAbsolutePath}/`, root);
        } else {
            let filenameTokens = fileAbsolutePath.split('.');
            let filenameLabel = filenameTokens[0];
            // ensure only markdown is parsed
            if ( filenameTokens.length >= 2 && filenameTokens[1] === 'md'){
                register_entry(filenameLabel, 'index', root, relativePath, filename);
            }
        }
    });
}

var create_blog_history = function(root, buildPath, template){

    let content = "";
    let entryTemplate = fs.readFileSync(`templates/blog-thumbnail.html`, "utf8");
    let entryArray = [];
    for (let key in registered_blog_entries) {
        if (!registered_blog_entries.hasOwnProperty(key)) continue;
        entryArray.push(registered_blog_entries[key]);
    }
    entryArray.sort((a, b) => {
        if (a.timestamp > b.timestamp) {
            return -1;
        }
        if (a.timestamp < b.timestamp) {
            return 1;
        }
        return 0;
    });
    entryArray.forEach(entry => {
        let modifiedContent = entryTemplate.replace("<timestamp/>", entry.timestampLabel);
            modifiedContent = modifiedContent.replace("<contents/>", converter.makeHtml(entry.content));
            modifiedContent = modifiedContent.replace("<link/>", entry.href);
        content += modifiedContent;
        content += `<br> <hr> <br>`;
    });

    gulp.src(`templates/${template}.html`)
    .pipe(replace('<contents/>', content))
    .pipe(rename({
        dirname : "",
        basename: 'blog',
        extname: ".html"
    }))
    .pipe(gulp.dest(buildFolder));
}


var create_translate_history = function(root, buildPath, template){

    let content = "";
    let entryTemplate = fs.readFileSync(`templates/blog-thumbnail.html`, "utf8");
    let entryArray = [];
    for (let key in registered_translation_entries) {
        if (!registered_translation_entries.hasOwnProperty(key)) continue;
        entryArray.push(registered_translation_entries[key]);
    }
    entryArray.sort((a, b) => {
        if (a.timestamp > b.timestamp) {
            return -1;
        }
        if (a.timestamp < b.timestamp) {
            return 1;
        }
        return 0;
    });
    entryArray.forEach(entry => {
        let modifiedContent = entryTemplate.replace("<timestamp/>", entry.timestampLabel);
            modifiedContent = modifiedContent.replace("<contents/>", converter.makeHtml(entry.content));
            modifiedContent = modifiedContent.replace("<link/>", entry.href);
        content += modifiedContent;
        content += `<br> <hr> <br>`;
    });

    gulp.src(`templates/${template}.html`)
    .pipe(replace('<contents/>', content))
    .pipe(rename({
        dirname : "",
        basename: 'translation',
        extname: ".html"
    }))
    .pipe(gulp.dest(buildFolder));
}



var create_development_history = function(root, buildPath, template){

    let content = "";
    let entryTemplate = fs.readFileSync(`templates/blog-thumbnail.html`, "utf8");
    let entryArray = [];
    for (let key in registered_development_entries) {
        if (!registered_development_entries.hasOwnProperty(key)) continue;
        entryArray.push(registered_development_entries[key]);
    }
    entryArray.sort((a, b) => {
        if (a.timestamp > b.timestamp) {
            return -1;
        }
        if (a.timestamp < b.timestamp) {
            return 1;
        }
        return 0;
    });
    entryArray.forEach(entry => {
        let modifiedContent = entryTemplate.replace("<timestamp/>", entry.timestampLabel);
            modifiedContent = modifiedContent.replace("<contents/>", converter.makeHtml(entry.content));
            modifiedContent = modifiedContent.replace("<link/>", entry.href);
        content += modifiedContent;
        content += `<br> <hr> <br>`;
    });

    gulp.src(`templates/${template}.html`)
    .pipe(replace('<contents/>', content))
    .pipe(rename({
        dirname : "",
        basename: 'dev',
        extname: ".html"
    }))
    .pipe(gulp.dest(buildFolder));
}

var register_entry = function(label, template, root, directory, filename){
    let inputFilePath          = `${root}${directory}${filename}`;
    let relativeOutputFilePath = `/${directory}${filename}`;
    let basename               = filename.split('.')[0];
    gulp.task(label, function() {
        let fileContent = fs.readFileSync(inputFilePath, "utf8");

        // Detect all files to be copied and mark them
        let linkedFilesRegex = /(\[[^(\]|\[)]*\]\()([^(:|(\(|\)))]*.[^(md)])(\))/g;
        let match = linkedFilesRegex.exec(fileContent);
        while (match != null) {
            let sourceFilePath      = `${root}${directory}${match[2]}`;
            let destinationFilePath = `${buildFolder}/${directory}${match[2]}`;
            try {
                fsExtra.copySync(sourceFilePath, destinationFilePath);
            } catch (err) {
                console.error(err);
            }
            match = linkedFilesRegex.exec(fileContent);
        }

        // replace markdown links
        let markdownLinkRegex = /(\[[^(\]|\[)]*\]\([^(\(|\))]*.)(md)(\))/g;
        fileContent = fileContent.replace(markdownLinkRegex, "$1html$3");

        // change relative to absolute routes
        let documentLinkRegex = /(\[[^(\]|\[)]*\]\()([^((:)|((\(|\)))]*.[^(md)]\))/g;
        fileContent = fileContent.replace(documentLinkRegex, `$1/${directory}$2`);

        let blog_entry = false;
        let timestampLabel = "No Date";
        // if it is a blog entry, add it to the blog page
        if(/^\/blog\//g.test(relativeOutputFilePath)){
            blog_entry = true;
            let lines = fileContent.split("\n");
            let entryContent = "";
            // If you put a date comment anywhere, then it will be used as a date for the post.
            let timestamp = /\[\/\/\]: # \((\w+ \w+ \d+ \d+:\d+:\d+ .\d+ \d+)\)/g.exec(fileContent);

            if(timestamp !== null){
                timestampLabel = timestamp[1];
                timestamp = Date.parse(timestamp[1]);
            } else {
                timestamp = "0";
            }

            // concat all lines to generate the entry
            entryContent = lines.slice(0, 4).join("\n");

            registered_blog_entries[label] = {
                timestamp: timestamp,
                timestampLabel: timestampLabel,
                content: entryContent,
                href: `/${directory}${basename}.html`
            };

            blogMutex.acquire()
            .then(function(release) {
                create_blog_history(root, `${buildFolder}/`, template);
                release();
            });

        }

        // I'll have to srhink this shit later
        else if(/^\/translation\//g.test(relativeOutputFilePath)){
            blog_entry = true;
            let lines = fileContent.split("\n");
            let entryContent = "";
            // If you put a date comment anywhere, then it will be used as a date for the post.
            let timestamp = /\[\/\/\]: # \((\w+ \w+ \d+ \d+:\d+:\d+ .\d+ \d+)\)/g.exec(fileContent);

            if(timestamp !== null){
                timestampLabel = timestamp[1];
                timestamp = Date.parse(timestamp[1]);
            } else {
                timestamp = "0";
            }

            // concat all lines to generate the entry
            entryContent = lines.slice(0, 4).join("\n");

            registered_translation_entries[label] = {
                timestamp: timestamp,
                timestampLabel: timestampLabel,
                content: entryContent,
                href: `/${directory}${basename}.html`
            };

            translationMutex.acquire()
            .then(function(release) {
                create_translate_history(root, `${buildFolder}/`, template);
                release();
            });

        }

        // I'll have to srhink this shit later
        else if(/^\/dev\//g.test(relativeOutputFilePath)){
            blog_entry = true;
            let lines = fileContent.split("\n");
            let entryContent = "";
            // If you put a date comment anywhere, then it will be used as a date for the post.
            let timestamp = /\[\/\/\]: # \((\w+ \w+ \d+ \d+:\d+:\d+ .\d+ \d+)\)/g.exec(fileContent);

            if(timestamp !== null){
                timestampLabel = timestamp[1];
                timestamp = Date.parse(timestamp[1]);
            } else {
                timestamp = "0";
            }

            // concat all lines to generate the entry
            entryContent = lines.slice(0, 4).join("\n");

            registered_development_entries[label] = {
                timestamp: timestamp,
                timestampLabel: timestampLabel,
                content: entryContent,
                href: `/${directory}${basename}.html`
            };

            developmentMutex.acquire()
            .then(function(release) {
                create_development_history(root, `${buildFolder}/`, template);
                release();
            });

        }

        if(blog_entry){
            let entryTemplate = fs.readFileSync(`templates/blog-entry.html`, "utf8");
            entryTemplate = entryTemplate.replace("<timestamp/>", timestampLabel);
            entryTemplate = entryTemplate.replace("<contents/>", converter.makeHtml(fileContent));
            return gulp.src(`templates/${template}.html`)
            .pipe(replace('<contents/>', entryTemplate))
            .pipe(rename({dirname : directory, basename: basename, extname: ".html"}))
            .pipe(gulp.dest(buildFolder));
        }

        return gulp.src(`templates/${template}.html`)
        .pipe(replace('<contents/>', converter.makeHtml(fileContent)))
        .pipe(rename({
            dirname : directory,
            basename: basename,
            // prefix: "bonjour-",
            // suffix: "-hola",
            extname: ".html"
        }))
        .pipe(gulp.dest(buildFolder));

    });
    registered_top_pages.push(label);
    registered_watchers.push({
        input_file: inputFilePath,
        trigger   : [label]
    });
    registered_link_replacements.push(relativeOutputFilePath);
}

// this scans entries by default
scan_directory(entriesFolder, entriesFolder);

gulp.task('sass', function() {
    gulp.src('*.scss')
        .pipe(sass())
        .pipe(gulp.dest(function(f) {
            return `${f.base}build`;
        }));
});

gulp.task('webserver', function() {
    gulp.src('./docs')
    .pipe(server({
        defaultFile: 'index.html',
        livereload : true
        // open: true
    }));
});


gulp.task('default', ['sass', 'webserver', ...registered_top_pages], function() {
    gulp.watch('*.scss', ['sass']);
    registered_watchers.forEach(watched => {
        gulp.watch(watched.input_file, watched.trigger);
    });
});